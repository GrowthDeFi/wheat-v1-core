// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { Transfers } from "../modules/Transfers.sol";

import { DelayedActionGuard } from "../DelayedActionGuard.sol";

import { IERC20Historical } from "./IERC20Historical.sol";

contract RewardDistributor is ReentrancyGuard, DelayedActionGuard
{
	uint256 public constant MIN_ALLOC_TIME = 1 days;
	uint256 public constant CLAIM_BASIS = 1 weeks;

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
		firstClaimPeriod = (block.timestamp * CLAIM_BASIS) / CLAIM_BASIS;
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

	function claim(bool noPenalty) external returns (uint256 _amount)
	{
		IERC20Historical(escrowToken).checkpoint();
		allocateReward();
		uint256 _period = (lastAlloc / CLAIM_BASIS) * CLAIM_BASIS;
		if (noPenalty) _period -= 13 * CLAIM_BASIS;
		_amount = _claim(msg.sender, _period);
		Transfers._pushFunds(rewardToken, msg.sender, _amount);
		rewardBalance -= _amount;
		return _amount;
	}

	function _claim(address _account, uint256 _lastPeriod) internal returns (uint256 _amount)
	{
		uint256 _period = lastClaimPeriod[_account];
		if (_period > _lastPeriod) _lastPeriod = _period;
		lastClaimPeriod[_account] = _lastPeriod;
		if (_period == 0) _period = firstClaimPeriod;
		_amount = 0;
		while (_period < _lastPeriod) {
			_period += CLAIM_BASIS;
			uint256 _supply = IERC20Historical(escrowToken).totalSupply(_period);
			uint256 _balance = IERC20Historical(escrowToken).balanceOf(_account, _period);
			_amount += rewardPerPeriod[_period] * _balance / _supply;
		}
		emit Claimed(_account, _amount);
		return _amount;
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
	event Claimed(address indexed _account, uint256 _amount);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
}
