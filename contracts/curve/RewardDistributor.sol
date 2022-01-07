// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { DelayedActionGuard } from "../DelayedActionGuard.sol";

import { Transfers } from "../modules/Transfers.sol";

import { ValueEscrowToken } from "./ValueEscrowToken.sol";

contract RewardDistributor is ReentrancyGuard, DelayedActionGuard
{
	uint256 constant MIN_ALLOC_TIME = 1 days;

	address public immutable escrowToken;
	address public immutable rewardToken;

	uint256 public lastTime;
	uint256 public lastBalance;
	mapping(uint256 => uint256) public rewardPerWeek;

	uint256 public firstWeek;
	mapping(address => uint256) public lastClaimWeek;

	address public treasury;

	constructor(address _escrowToken, address _rewardToken, address _treasury) public
	{
		escrowToken = _escrowToken;
		rewardToken = _rewardToken;
		treasury = _treasury;
		lastTime = block.timestamp;
		firstWeek = (block.timestamp * 1 weeks) / 1 weeks;
	}

	function allocateReward() public returns (uint256 _amount)
	{
		uint256 _oldTime = lastTime;
		uint256 _newTime = block.timestamp;
		uint256 _time = _newTime - _oldTime;
		if (_time < MIN_ALLOC_TIME) return 0;
		uint256 _oldBalance = lastBalance;
		uint256 _newBalance = Transfers._getBalance(rewardToken);
		uint256 _balance = _newBalance - _oldBalance;
		lastTime = _newTime;
		lastBalance = _newBalance;
		if (_balance == 0) return 0;
		uint256 _start = _oldTime;
		uint256 _week = (_start / 1 weeks) * 1 weeks;
		while (true) {
			uint256 _nextWeek = _week + 1 weeks;
			uint256 _end = _nextWeek < _newTime ? _nextWeek : _newTime;
			rewardPerWeek[_nextWeek] += _balance * (_start - _end) / _time;
			if (_end == _newTime) break;
			_start = _end;
			_week = _nextWeek;
		}
		emit AllocateReward(_balance);
		return _balance;
	}

	function claim() external returns (uint256 _amount)
	{
		return claim(msg.sender);
	}

	function claim(address _account) public nonReentrant returns (uint256 _amount)
	{
		ValueEscrowToken(escrowToken).checkpoint();
		allocateReward();
		uint256 _week = (lastTime / 1 weeks) * 1 weeks;
		_amount = _claim(_account, _week);
		Transfers._pushFunds(rewardToken, _account, _amount);
		lastBalance -= _amount;
		return _amount;
	}

	function claimBatch(address[] calldata _accounts) external nonReentrant returns (uint256[] memory _amounts)
	{
		ValueEscrowToken(escrowToken).checkpoint();
		allocateReward();
		uint256 _week = (lastTime / 1 weeks) * 1 weeks;
		_amounts = new uint256[](_accounts.length);
		uint256 _totalAmount = 0;
		for (uint256 _i = 0; _i < _accounts.length; _i++) {
			address _account = _accounts[_i];
			uint256 _amount = _claim(_account, _week);
			Transfers._pushFunds(rewardToken, _account, _amount);
			_totalAmount += _amount;
			_amounts[_i] = _amount;
		}
		lastBalance -= _totalAmount;
		return _amounts;
	}

	function _claim(address _account, uint256 _lastWeek) internal returns (uint256 _amount)
	{
		uint256 _week = lastClaimWeek[_account];
		lastClaimWeek[_account] = _lastWeek;
		if (_week == 0) _week = firstWeek;
		_amount = 0;
		while (_week < _lastWeek) {
			_week += 1 weeks;
			uint256 _supply = ValueEscrowToken(escrowToken).totalSupply(_week);
			uint256 _balance = ValueEscrowToken(escrowToken).balanceOf(_account, _week);
			_amount += rewardPerWeek[_week] * _balance / _supply;
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
