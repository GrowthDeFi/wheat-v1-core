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

	uint256 constant DEFAULT_PENALTY_RATE = 50e16; // 50%
	uint256 constant DEFAULT_PENALTY_PERIODS = 13; // 13 weeks
	uint256 constant MAXIMUM_PENALTY_PERIODS = 5 * 52; // ~5 years

	address public immutable escrowToken;
	address public immutable rewardToken;
	address public immutable boostToken;

	uint256 public penaltyRate = DEFAULT_PENALTY_RATE;
	uint256 public penaltyPeriods = DEFAULT_PENALTY_PERIODS;
	address public penaltyRecipient = FURNACE;

	address public treasury;

	uint256 private lastAlloc_;
	uint256 private rewardBalance_;
	mapping(uint256 => uint256) private rewardPerPeriod_;

	uint256 private immutable firstPeriod_;
	mapping(address => uint256) private lastPeriod_;

	constructor(address _escrowToken, address _rewardToken, address _boostToken, address _treasury) public
	{
		escrowToken = _escrowToken;
		rewardToken = _rewardToken;
		boostToken = _boostToken;
		treasury = _treasury;
		lastAlloc_ = block.timestamp;
		firstPeriod_ = (block.timestamp / CLAIM_BASIS + 1) * CLAIM_BASIS;
	}

	function unallocated() external view returns (uint256 _amount)
	{
		uint256 _oldTime = lastAlloc_;
		uint256 _newTime = block.timestamp;
		uint256 _time = _newTime - _oldTime;
		if (_time < MIN_ALLOC_TIME) return 0;
		uint256 _oldBalance = rewardBalance_;
		uint256 _newBalance = Transfers._getBalance(rewardToken);
		uint256 _balance = _newBalance - _oldBalance;
		return _balance;
	}

	function allocate() public returns (uint256 _amount)
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
		emit Allocate(_balance);
		return _balance;
	}

	function available(address _account, bool _noPenalty) external view returns (uint256 _amount, uint256 _penalty)
	{
		(_amount, _penalty,,) = _claim(_account, _noPenalty);
		return (_amount, _penalty);
	}

	function claim(bool _noPenalty) external nonReentrant returns (uint256 _amount, uint256 _penalty)
	{
		IERC20Historical(escrowToken).checkpoint();
		allocate();
		uint256 _excess;
		(_amount, _penalty, _excess, lastPeriod_[msg.sender]) = _claim(msg.sender, _noPenalty);
		rewardBalance_ -= _amount + _penalty + _excess;
		Transfers._pushFunds(rewardToken, msg.sender, _amount);
		Transfers._pushFunds(rewardToken, penaltyRecipient, _penalty);
		if (_amount > 0 || _penalty > 0) {
			emit Claim(msg.sender, _amount, _penalty);
		}
		if (_excess > 0) {
			emit Recycle(_excess);
		}
		return (_amount, _penalty);
	}

	function unrecycled() external view returns (uint256 _amount)
	{
		(_amount,) = _recycle();
		return _amount;
	}

	function recycle() external returns (uint256 _amount)
	{
		IERC20Historical(escrowToken).checkpoint();
		allocate();
		uint256 _excess;
		(_excess, lastPeriod_[address(0)]) = _recycle();
		rewardBalance_ -= _excess;
		emit Recycle(_excess);
		return _excess;
	}

	function _calculateAccrued(address _account, uint256 _firstPeriod, uint256 _lastPeriod) internal view returns (uint256 _amount, uint256 _excess)
	{
		_amount = 0;
		_excess = 0;
		if (boostToken == address(0)) {
			for (uint256 _period = _firstPeriod; _period < _lastPeriod; _period += CLAIM_BASIS) {
				uint256 _totalSupply = IERC20Historical(escrowToken).totalSupply(_period);
				if (_totalSupply > 0) {
					uint256 _balance = IERC20Historical(escrowToken).balanceOf(_account, _period);
					uint256 _rewardPerPeriod = rewardPerPeriod_[_period];
					_amount += _rewardPerPeriod * _balance / _totalSupply;
				}
			}
		} else {
			for (uint256 _period = _firstPeriod; _period < _lastPeriod; _period += CLAIM_BASIS) {
				uint256 _totalSupply = IERC20Historical(escrowToken).totalSupply(_period);
				uint256 _boostTotalSupply = IERC20Historical(boostToken).totalSupply(_period);
				uint256 _normalizedTotalSupply = 10 * _totalSupply * _boostTotalSupply;
				if (_normalizedTotalSupply > 0) {
					uint256 _balance = IERC20Historical(escrowToken).balanceOf(_account, _period);
					uint256 _boostBalance = IERC20Historical(boostToken).balanceOf(_account, _period);
					uint256 _isolatedBalance = 10 * _balance * _boostTotalSupply;
					uint256 _normalizedBalance = 4 * _balance * _boostTotalSupply + 6 * _totalSupply * _boostBalance;
					uint256 _limitedBalance = _normalizedBalance > _isolatedBalance ? _isolatedBalance : _normalizedBalance;
					uint256 _exceededBalance = _normalizedBalance - _limitedBalance;
					uint256 _rewardPerPeriod = rewardPerPeriod_[_period];
					_amount += _rewardPerPeriod * _limitedBalance / _normalizedTotalSupply;
					_excess += _rewardPerPeriod * _exceededBalance / _normalizedTotalSupply;
				}
			}
		}
		return (_amount, _excess);
	}

	function _calculateAccrued(uint256 _firstPeriod, uint256 _lastPeriod) internal view returns (uint256 _amount)
	{
		_amount = 0;
		if (boostToken == address(0)) {
			for (uint256 _period = _firstPeriod; _period < _lastPeriod; _period += CLAIM_BASIS) {
				uint256 _totalSupply = IERC20Historical(escrowToken).totalSupply(_period);
				if (_totalSupply == 0) {
					_amount += rewardPerPeriod_[_period];
				}
			}
		} else {
			for (uint256 _period = _firstPeriod; _period < _lastPeriod; _period += CLAIM_BASIS) {
				uint256 _totalSupply = IERC20Historical(escrowToken).totalSupply(_period);
				uint256 _boostTotalSupply = IERC20Historical(boostToken).totalSupply(_period);
				uint256 _normalizedTotalSupply = 10 * _boostTotalSupply * _totalSupply;
				if (_normalizedTotalSupply == 0) {
					_amount += rewardPerPeriod_[_period];
				}
			}
		}
		return _amount;
	}

	function _claim(address _account, bool _noPenalty) internal view returns (uint256 _amount, uint256 _penalty, uint256 _excess, uint256 _period)
	{
		uint256 _firstPeriod = lastPeriod_[_account];
		if (_firstPeriod < firstPeriod_) _firstPeriod = firstPeriod_;
		uint256 _lastPeriod = (lastAlloc_ / CLAIM_BASIS + 1) * CLAIM_BASIS;
		uint256 _middlePeriod =_lastPeriod - penaltyPeriods * CLAIM_BASIS;
		if (_middlePeriod < _firstPeriod) _middlePeriod = _firstPeriod;
		if (_noPenalty) _lastPeriod = _middlePeriod;
		(uint256 _amount1, uint256 _excess1) = _calculateAccrued(_account, _firstPeriod, _middlePeriod);
		(uint256 _amount2, uint256 _excess2) = _calculateAccrued(_account, _middlePeriod, _lastPeriod);
		_penalty = _amount2 * penaltyRate / 100e16;
		_amount = _amount1 + (_amount2 - _penalty);
		_excess = _excess1 + _excess2;
		return (_amount, _penalty, _excess, _lastPeriod);
	}

	function _recycle() internal view returns (uint256 _excess, uint256 _period)
	{
		uint256 _firstPeriod = lastPeriod_[address(0)];
		if (_firstPeriod < firstPeriod_) _firstPeriod = firstPeriod_;
		uint256 _lastPeriod = (lastAlloc_ / CLAIM_BASIS + 1) * CLAIM_BASIS;
		_excess = _calculateAccrued(_firstPeriod, _lastPeriod);
		return (_excess, _lastPeriod);
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
		delayed(this.recoverLostFunds.selector, keccak256(abi.encode(_token)))
	{
		require(_token != rewardToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	function setPenaltyParams(uint256 _newPenaltyRate, uint256 _newPenaltyPeriods, address _newPenaltyRecipient) external onlyOwner
		delayed(this.setPenaltyParams.selector, keccak256(abi.encode(_newPenaltyRate, _newPenaltyPeriods, _newPenaltyRecipient)))
	{
		require(_newPenaltyRate <= 100e16, "invalid rate");
		require(_newPenaltyPeriods <= MAXIMUM_PENALTY_PERIODS, "invalid periods");
		require(_newPenaltyRecipient != address(0), "invalid recipient");
		(uint256 _oldPenaltyRate, uint256 _oldPenaltyPeriods, address _oldPenaltyRecipient) = (penaltyRate, penaltyPeriods, penaltyRecipient);
		(penaltyRate, penaltyPeriods, penaltyRecipient) = (_newPenaltyRate, _newPenaltyPeriods, _newPenaltyRecipient);
		emit ChangePenaltyParams(_oldPenaltyRate, _oldPenaltyPeriods, _newPenaltyRate, _newPenaltyPeriods, _oldPenaltyRecipient, _newPenaltyRecipient);
	}

	function setTreasury(address _newTreasury) external onlyOwner
		delayed(this.setTreasury.selector, keccak256(abi.encode(_newTreasury)))
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	event Allocate(uint256 _amount);
	event Claim(address indexed _account, uint256 _amount, uint256 _penalty);
	event Recycle(uint256 _amount);
	event ChangePenaltyParams(uint256 _oldPenaltyRate, uint256 _oldPenaltyPeriods, uint256 _newPenaltyRate, uint256 _newPenaltyPeriods, address _oldPenaltyRecipient, address _newPenaltyRecipient);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
}
