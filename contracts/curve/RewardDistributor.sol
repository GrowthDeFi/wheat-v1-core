// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { Transfers } from "../modules/Transfers.sol";

import { DelayedActionGuard } from "../DelayedActionGuard.sol";

import { IERC20Historical } from "./IERC20Historical.sol";

contract RewardDistributor is ReentrancyGuard, DelayedActionGuard
{
	address constant public FURNACE = 0x000000000000000000000000000000000000dEaD;

	uint256 public constant CLAIM_BASIS = 1 weeks;
	uint256 public constant MIN_ALLOC_TIME = 1 days;

	address public immutable escrowToken;
	address public immutable rewardToken;
	address public immutable boostToken;

	address public treasury;

	uint256 private lastAlloc_;
	uint256 private rewardBalance_;
	mapping(uint256 => uint256) private rewardPerPeriod_;

	uint256 private immutable firstClaimPeriod_;
	mapping(address => uint256) private lastClaimPeriod_;

	constructor(address _escrowToken, address _rewardToken, address _boostToken, address _treasury) public
	{
		escrowToken = _escrowToken;
		rewardToken = _rewardToken;
		boostToken = _boostToken;
		treasury = _treasury;
		lastAlloc_ = block.timestamp;
		firstClaimPeriod_ = (block.timestamp / CLAIM_BASIS + 1) * CLAIM_BASIS;
	}

	function allocateReward() public returns (uint256 _amount)
	{
		uint256 _oldTime = lastAlloc_;
		uint256 _newTime = block.timestamp;
		uint256 _time = _newTime - _oldTime;
		if (_time < MIN_ALLOC_TIME) return 0;
		uint256 _oldBalance = rewardBalance_;
		uint256 _newBalance = Transfers._getBalance(rewardToken);
		uint256 _balance = _newBalance - _oldBalance;
		uint256 _maxBalance = uint256(-1) / _time;
		if (_balance > _maxBalance) {
			_balance = _maxBalance;
			_newBalance = _oldBalance + _balance;
		}
		lastAlloc_ = _newTime;
		rewardBalance_ = _newBalance;
		if (_balance == 0) return 0;
		uint256 _start = _oldTime;
		uint256 _period = (_start / CLAIM_BASIS) * CLAIM_BASIS;
		while (true) {
			uint256 _nextPeriod = _period + CLAIM_BASIS;
			uint256 _end = _nextPeriod < _newTime ? _nextPeriod : _newTime;
			rewardPerPeriod_[_nextPeriod] += _balance * (_start - _end) / _time;
			if (_end == _newTime) break;
			_start = _end;
			_period = _nextPeriod;
		}
		emit AllocateReward(_balance);
		return _balance;
	}

	function pendingReward(address _account, bool _noPenalty) external view returns (uint256 _amount, uint256 _penalty)
	{
		(_amount, _penalty,,) = _claim(_account, _noPenalty);
		return (_amount, _penalty);
	}

	function claim(bool _noPenalty) external nonReentrant returns (uint256 _amount, uint256 _penalty)
	{
		IERC20Historical(escrowToken).checkpoint();
		allocateReward();
		uint256 _excess;
		(_amount, _penalty, _excess, lastClaimPeriod_[msg.sender]) = _claim(msg.sender, _noPenalty);
		rewardBalance_ -= _amount + _penalty + _excess;
		Transfers._pushFunds(rewardToken, msg.sender, _amount);
		Transfers._pushFunds(rewardToken, FURNACE, _penalty);
		emit Claimed(msg.sender, _amount, _penalty);
		return (_amount, _penalty);
	}

	function _calculateAccruedReward(address _account, uint256 _firstPeriod, uint256 _lastPeriod) internal view returns (uint256 _amount, uint256 _excess)
	{
		_amount = 0;
		_excess = 0;
		address _escrowToken = escrowToken;
		address _boostToken = boostToken;
		if (_boostToken == address(0)) {
			for (uint256 _period = _firstPeriod; _period < _lastPeriod; _period += CLAIM_BASIS) {
				uint256 _totalSupply = 1 + IERC20Historical(_escrowToken).totalSupply(_period);
				uint256 _balance = IERC20Historical(_escrowToken).balanceOf(_account, _period);
				_amount += rewardPerPeriod_[_period] * _balance / _totalSupply;
			}
		} else {
			for (uint256 _period = _firstPeriod; _period < _lastPeriod; _period += CLAIM_BASIS) {
				uint256 _totalSupply = 1 + IERC20Historical(_escrowToken).totalSupply(_period);
				uint256 _balance = IERC20Historical(_escrowToken).balanceOf(_account, _period);
				uint256 _boostTotalSupply = 1 + IERC20Historical(_boostToken).totalSupply(_period);
				uint256 _boostBalance = IERC20Historical(_boostToken).balanceOf(_account, _period);
				uint256 _normalizedBalance = 4 * _balance * _boostTotalSupply + 6 * _boostBalance * _totalSupply;
				uint256 _normalizedTotalSupply = 10 * _boostTotalSupply * _totalSupply;
				uint256 _limitedBalance = _normalizedBalance > _balance ? _balance : _normalizedBalance;
				uint256 _exceededBalance = _normalizedBalance - _limitedBalance;
				_amount += rewardPerPeriod_[_period] * _limitedBalance / _normalizedTotalSupply;
				_excess += rewardPerPeriod_[_period] * _exceededBalance / _normalizedTotalSupply;
			}
		}
		return (_amount, _excess);
	}

	function _claim(address _account, bool _noPenalty) internal view returns (uint256 _amount, uint256 _penalty, uint256 _excess, uint256 _period)
	{
		uint256 _firstPeriod = lastClaimPeriod_[_account];
		if (_firstPeriod < firstClaimPeriod_) _firstPeriod = firstClaimPeriod_;
		uint256 _lastPeriod = (lastAlloc_ / CLAIM_BASIS + 1) * CLAIM_BASIS;
		uint256 _middlePeriod =_lastPeriod - 13 * CLAIM_BASIS; // 13 weeks
		if (_middlePeriod < _firstPeriod) _middlePeriod = _firstPeriod;
		if (_noPenalty) _lastPeriod = _middlePeriod;
		(uint256 _amount1, uint256 _excess1) = _calculateAccruedReward(_account, _firstPeriod, _middlePeriod);
		(uint256 _amount2, uint256 _excess2) = _calculateAccruedReward(_account, _middlePeriod, _lastPeriod);
		_penalty = _amount2 / 2; // 50%
		_amount = _amount1 + (_amount2 - _penalty);
		_excess = _excess1 + _excess2;
		return (_amount, _penalty, _excess, _lastPeriod);
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
		delayed(this.recoverLostFunds.selector, keccak256(abi.encode(_token)))
	{
		require(_token != rewardToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	function setTreasury(address _newTreasury) external onlyOwner
		delayed(this.setTreasury.selector, keccak256(abi.encode(_newTreasury)))
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	event AllocateReward(uint256 _amount);
	event Claimed(address indexed _account, uint256 _amount, uint256 _penalty);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
}
