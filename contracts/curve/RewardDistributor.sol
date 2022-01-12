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

	uint256 public lastAlloc;
	uint256 public rewardBalance;
	mapping(uint256 => uint256) public rewardPerPeriod;

	uint256 public immutable firstClaimPeriod;
	mapping(address => uint256) public lastClaimPeriod;

	address public treasury;

	constructor(address _escrowToken, address _rewardToken, address _treasury) public
	{
		escrowToken = _escrowToken;
		rewardToken = _rewardToken;
		treasury = _treasury;
		lastAlloc = block.timestamp;
		firstClaimPeriod = (block.timestamp / CLAIM_BASIS + 1) * CLAIM_BASIS;
	}

	function allocateReward() public returns (uint256 _amount)
	{
		uint256 _oldTime = lastAlloc;
		uint256 _newTime = block.timestamp;
		uint256 _time = _newTime - _oldTime;
		if (_time < MIN_ALLOC_TIME) return 0;
		uint256 _oldBalance = rewardBalance;
		uint256 _newBalance = Transfers._getBalance(rewardToken);
		uint256 _balance = _newBalance - _oldBalance;
		uint256 _maxBalance = uint256(-1) / _time;
		if (_balance > _maxBalance) {
			_balance = _maxBalance;
			_newBalance = _oldBalance + _balance;
		}
		lastAlloc = _newTime;
		rewardBalance = _newBalance;
		if (_balance == 0) return 0;
		uint256 _start = _oldTime;
		uint256 _period = (_start / CLAIM_BASIS) * CLAIM_BASIS;
		while (true) {
			uint256 _nextPeriod = _period + CLAIM_BASIS;
			uint256 _end = _nextPeriod < _newTime ? _nextPeriod : _newTime;
			rewardPerPeriod[_nextPeriod] += _balance * (_start - _end) / _time;
			if (_end == _newTime) break;
			_start = _end;
			_period = _nextPeriod;
		}
		emit AllocateReward(_balance);
		return _balance;
	}

	function pendingReward(address _account, bool _noPenalty) external view returns (uint256 _amount, uint256 _penalty)
	{
		(_amount, _penalty,) = _claim(_account, _noPenalty);
		return (_amount, _penalty);
	}

	function claim(bool _noPenalty) external nonReentrant returns (uint256 _amount, uint256 _penalty)
	{
		allocateReward();
		IERC20Historical(escrowToken).checkpoint();
		(_amount, _penalty, lastClaimPeriod[msg.sender]) = _claim(msg.sender, _noPenalty);
		rewardBalance -= _amount + _penalty;
		Transfers._pushFunds(rewardToken, msg.sender, _amount);
		Transfers._pushFunds(rewardToken, FURNACE, _penalty);
		emit Claimed(msg.sender, _amount, _penalty);
		return (_amount, _penalty);
	}

	function _calculateAccruedReward(address _account, uint256 _firstPeriod, uint256 _lastPeriod) internal view returns (uint256 _amount)
	{
		_amount = 0;
		for (uint256 _period = _firstPeriod; _period < _lastPeriod; _period += CLAIM_BASIS) {
			uint256 _totalSupply = IERC20Historical(escrowToken).totalSupply(_period);
			if (_totalSupply > 0) {
				uint256 _balance = IERC20Historical(escrowToken).balanceOf(_account, _period);
				_amount += rewardPerPeriod[_period] * _balance / _totalSupply;
			}
		}
		return _amount;
	}

	function _claim(address _account, bool _noPenalty) internal view returns (uint256 _amount, uint256 _penalty, uint256 _period)
	{
		uint256 _firstPeriod = lastClaimPeriod[_account];
		if (_firstPeriod < firstClaimPeriod) _firstPeriod = firstClaimPeriod;
		uint256 _lastPeriod = (lastAlloc / CLAIM_BASIS + 1) * CLAIM_BASIS;
		uint256 _middlePeriod =_lastPeriod - 13 * CLAIM_BASIS; // 13 weeks
		if (_middlePeriod < _firstPeriod) _middlePeriod = _firstPeriod;
		if (_noPenalty) _lastPeriod = _middlePeriod;
		uint256 _amount1 = _calculateAccruedReward(_account, _firstPeriod, _middlePeriod);
		uint256 _amount2 = _calculateAccruedReward(_account, _middlePeriod, _lastPeriod);
		_penalty = _amount2 / 2; // 50%
		_amount = _amount1 + (_amount2 - _penalty);
		return (_amount, _penalty, _lastPeriod);
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
