// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

contract Buyback is ReentrancyGuard, WhitelistGuard
{
	using SafeMath for uint256;

	uint256 constant DEFAULT_REWARD_BUYBACK1_SHARE = 70e16; // 70%
	uint256 constant DEFAULT_REWARD_BUYBACK2_SHARE = 15e16; // 15%
	uint256 constant DEFAULT_REWARD_YIELD_SHARE = 15e16; // 15%

	address constant public FURNACE = 0x000000000000000000000000000000000000dEaD;

	address public immutable rewardToken;
	address public immutable routingToken;
	address public immutable buybackToken1;
	address public immutable buybackToken2;

	address public exchange;
	address public treasury;
	address public yield;

	uint256 public rewardBuyback1Share = DEFAULT_REWARD_BUYBACK1_SHARE;
	uint256 public rewardBuyback2Share = DEFAULT_REWARD_BUYBACK2_SHARE;
	uint256 public rewardYieldShare = DEFAULT_REWARD_YIELD_SHARE;

	constructor (address _rewardToken, address _routingToken, address _buybackToken1, address _buybackToken2, address _treasury, address _yield) public
	{
		rewardToken = _rewardToken;
		routingToken = _routingToken;
		buybackToken1 = _buybackToken1;
		buybackToken2 = _buybackToken2;
		treasury = _treasury;
		yield = _yield;
	}

	function pendingBuyback() external view returns (uint256 _buybackAmount)
	{
		return Transfers._getBalance(rewardToken);
	}

	function gulp() external onlyEOAorWhitelist nonReentrant
	{
		require(exchange != address(0), "exchange not set");
		if (routingToken != rewardToken) {
			uint256 _balance = Transfers._getBalance(rewardToken);
			Transfers._approveFunds(rewardToken, exchange, _balance);
			IExchange(exchange).convertFundsFromInput(rewardToken, routingToken, _balance, 1);
		}
		uint256 _total = Transfers._getBalance(routingToken);
		uint256 _amount1 = _total.mul(DEFAULT_REWARD_BUYBACK1_SHARE) / 1e18;
		uint256 _amount2 = _total.mul(DEFAULT_REWARD_BUYBACK2_SHARE) / 1e18;
		uint256 _burning = _amount1 + _amount2;
		uint256 _sending = _total - _burning;
		Transfers._approveFunds(routingToken, exchange, _burning);
		uint256 _burning1 = IExchange(exchange).convertFundsFromInput(routingToken, buybackToken1, _amount1, 1);
		uint256 _amount3 = IExchange(exchange).convertFundsFromInput(routingToken, buybackToken2, _amount2, 1);
		uint256 _burning2 = _amount3 / 2;
		uint256 _sending2 = _amount3 - _burning2;
		_burn(buybackToken1, _burning1);
		_burn(buybackToken2, _burning2);
		_send(buybackToken2, treasury, _sending2);
		_send(routingToken, yield, _sending);
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
	{
		require(_token != rewardToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	function setExchange(address _newExchange) external onlyOwner nonReentrant
	{
		address _oldExchange = exchange;
		exchange = _newExchange;
		emit ChangeExchange(_oldExchange, _newExchange);
	}

	function setTreasury(address _newTreasury) external onlyOwner nonReentrant
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	function setYield(address _newYield) external onlyOwner nonReentrant
	{
		require(_newYield != address(0), "invalid address");
		address _oldYield = yield;
		yield = _newYield;
		emit ChangeYield(_oldYield, _newYield);
	}

	function setRewardSplit(uint256 _newRewardBuyback1Share, uint256 _newRewardBuyback2Share, uint256 _newRewardYieldShare) external onlyOwner nonReentrant
	{
		require(_newRewardBuyback1Share <= 1e18, "invalid rate");
		require(_newRewardBuyback2Share <= 1e18, "invalid rate");
		require(_newRewardYieldShare <= 1e18, "invalid rate");
		require(_newRewardBuyback1Share + _newRewardBuyback2Share + _newRewardYieldShare == 1e18, "invalid split");
		uint256 _oldRewardBuyback1Share = rewardBuyback1Share;
		uint256 _oldRewardBuyback2Share = rewardBuyback2Share;
		uint256 _oldRewardYieldShare = rewardYieldShare;
		rewardBuyback1Share = _newRewardBuyback1Share;
		rewardBuyback2Share = _newRewardBuyback2Share;
		rewardYieldShare = _newRewardYieldShare;
		emit ChangeRewardSplit(_oldRewardBuyback1Share, _oldRewardBuyback2Share, _oldRewardYieldShare, _newRewardBuyback1Share, _newRewardBuyback2Share, _newRewardYieldShare);
	}

	function _burn(address _token, uint256 _amount) internal
	{
		Transfers._pushFunds(_token, FURNACE, _amount);
	}

	function _send(address _token, address _to, uint256 _amount) internal
	{
		Transfers._pushFunds(_token, _to, _amount);
	}

	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeYield(address _oldYield, address _newYield);
	event ChangeRewardSplit(uint256 _oldRewardBuyback1Share, uint256 _oldRewardBuyback2Share, uint256 _oldRewardYieldShare, uint256 _newRewardBuyback1Share, uint256 _newRewardBuyback2Share, uint256 _newRewardYieldShare);
}
