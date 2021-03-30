// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { Exchange } from "./Exchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

contract Buyback is ReentrancyGuard, WhitelistGuard
{
	using SafeMath for uint256;

	uint256 constant DEFAULT_REWARD_BUYBACK1_SHARE = 70e16; // 70%
	uint256 constant DEFAULT_REWARD_BUYBACK2_SHARE = 15e16; // 15%
	uint256 constant DEFAULT_REWARD_RESERVE_SHARE = 15e16; // 15%

	address public immutable rewardToken;
	address public immutable routingToken;
	address public immutable buybackToken1;
	address public immutable buybackToken2;

	address public exchange;
	address public reserve;

	uint256 public rewardBuyback1Share = DEFAULT_REWARD_BUYBACK1_SHARE;
	uint256 public rewardBuyback2Share = DEFAULT_REWARD_BUYBACK2_SHARE;
	uint256 public rewardReserveShare = DEFAULT_REWARD_RESERVE_SHARE;

	constructor (address _rewardToken, address _routingToken, address _buybackToken1, address _buybackToken2) public
	{
		rewardToken = _rewardToken;
		routingToken = _routingToken;
		buybackToken1 = _buybackToken1;
		buybackToken2 = _buybackToken2;
	}

	function gulp() external onlyEOAorWhitelist nonReentrant
	{
		_gulp();
	}

	function setExchange(address _newExchange) external onlyOwner nonReentrant
	{
		address _oldExchange = exchange;
		exchange = _newExchange;
		emit ChangeExchange(_oldExchange, _newExchange);
	}

	function setReserve(address _newReserve) external onlyOwner nonReentrant
	{
		address _oldReserve = reserve;
		reserve = _newReserve;
		emit ChangeReserve(_oldReserve, _newReserve);
	}

	function setRewardSplit(uint256 _newRewardBuyback1Share, uint256 _newRewardBuyback2Share, uint256 _newRewardReserveShare) external onlyOwner nonReentrant
	{
		require(_newRewardBuyback1Share <= 1e18, "invalid rate");
		require(_newRewardBuyback2Share <= 1e18, "invalid rate");
		require(_newRewardReserveShare <= 1e18, "invalid rate");
		require(_newRewardBuyback1Share + _newRewardBuyback2Share + _newRewardReserveShare == 1e18, "invalid split");
		uint256 _oldRewardBuyback1Share = rewardBuyback1Share;
		uint256 _oldRewardBuyback2Share = rewardBuyback2Share;
		uint256 _oldRewardReserveShare = rewardReserveShare;
		rewardBuyback1Share = _newRewardBuyback1Share;
		rewardBuyback2Share = _newRewardBuyback2Share;
		rewardReserveShare = _newRewardReserveShare;
		emit ChangeRewardSplit(_oldRewardBuyback1Share, _oldRewardBuyback2Share, _oldRewardReserveShare, _newRewardBuyback1Share, _newRewardBuyback2Share, _newRewardReserveShare);
	}

	function _gulp() internal
	{
		require(exchange != address(0), "exchange not set");
		uint256 _balance = Transfers._getBalance(rewardToken);
		Transfers._approveFunds(rewardToken, exchange, _balance);
		uint256 _total = Exchange(exchange).convertFundsFromInput(rewardToken, routingToken, _balance, 1);
		uint256 _amount1 = _total.mul(DEFAULT_REWARD_BUYBACK1_SHARE) / 1e18;
		uint256 _amount2 = _total.mul(DEFAULT_REWARD_BUYBACK2_SHARE) / 1e18;
		uint256 _burning = _amount1 + _amount2;
		uint256 _sending = _total - _burning;
		Transfers._approveFunds(routingToken, exchange, _burning);
		uint256 _burning1 = Exchange(exchange).convertFundsFromInput(routingToken, buybackToken1, _amount1, 1);
		_burn(buybackToken1, _burning1);
		uint256 _burning2 = Exchange(exchange).convertFundsFromInput(routingToken, buybackToken2, _amount2, 1);
		_burn(buybackToken2, _burning2);
		_send(routingToken, _sending);
	}

	function _burn(address _token, uint256 _amount) internal
	{
		Transfers._pushFunds(_token, address(0), _amount);
	}

	function _send(address _token, uint256 _amount) internal
	{
		require(reserve != address(0), "reserve not set");
		Transfers._pushFunds(_token, reserve, _amount);
	}

	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeReserve(address _oldReserve, address _newReserve);
	event ChangeRewardSplit(uint256 _oldRewardBuyback1Share, uint256 _oldRewardBuyback2Share, uint256 _oldRewardReserveShare, uint256 _newRewardBuyback1Share, uint256 _newRewardBuyback2Share, uint256 _newRewardReserveShare);
}
