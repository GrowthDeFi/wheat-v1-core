// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { PantherToken } from "./interop/PantherSwap.sol";

contract PantherSwapBuyback is ReentrancyGuard, WhitelistGuard
{
	using SafeMath for uint256;

	uint256 constant DEFAULT_REWARD_BUYBACK1_SHARE = 70e16; // 70%
	uint256 constant DEFAULT_REWARD_BUYBACK2_SHARE = 30e16; // 30%

	address constant public FURNACE = 0x000000000000000000000000000000000000dEaD;

	address public immutable rewardToken;
	address public immutable buybackToken1;
	address public immutable buybackToken2;

	address public exchange;
	address public treasury;

	uint256 public rewardBuyback1Share = DEFAULT_REWARD_BUYBACK1_SHARE;
	uint256 public rewardBuyback2Share = DEFAULT_REWARD_BUYBACK2_SHARE;

	uint256 public lastGulpTime;

	constructor (address _rewardToken, address _buybackToken1, address _buybackToken2, address _treasury) public
	{
		rewardToken = _rewardToken;
		buybackToken1 = _buybackToken1;
		buybackToken2 = _buybackToken2;
		treasury = _treasury;
	}

	function pendingBuyback() external view returns (uint256 _buybackAmount)
	{
		return Transfers._getBalance(rewardToken);
	}

	function pendingBurning() external view returns (uint256 _burning1, uint256 _burning2)
	{
		require(exchange != address(0), "exchange not set");
		uint256 _balance = Transfers._getBalance(rewardToken);
		uint256 _amount1 = _balance.mul(DEFAULT_REWARD_BUYBACK1_SHARE) / 1e18;
		uint256 _amount2 = _balance.mul(DEFAULT_REWARD_BUYBACK2_SHARE) / 1e18;
		(_amount1, _amount2) = _capSplitAmount(_amount1, _amount2);
		_burning1 = IExchange(exchange).calcConversionFromInput(rewardToken, buybackToken1, _amount1);
		_burning2 = IExchange(exchange).calcConversionFromInput(rewardToken, buybackToken2, _amount2);
		return (_burning1, _burning2);
	}

	function gulp(uint256 _minBurning1, uint256 _minBurning2) external onlyEOAorWhitelist nonReentrant
	{
		require(exchange != address(0), "exchange not set");
		uint256 _balance = Transfers._getBalance(rewardToken);
		uint256 _amount1 = _balance.mul(DEFAULT_REWARD_BUYBACK1_SHARE) / 1e18;
		uint256 _amount2 = _balance.mul(DEFAULT_REWARD_BUYBACK2_SHARE) / 1e18;
		(_amount1, _amount2) = _capSplitAmount(_amount1, _amount2);
		Transfers._approveFunds(rewardToken, exchange, _amount1 + _amount2);
		IExchange(exchange).convertFundsFromInput(rewardToken, buybackToken1, _amount1, 1);
		IExchange(exchange).convertFundsFromInput(rewardToken, buybackToken2, _amount2, 1);
		uint256 _burning1 = Transfers._getBalance(buybackToken1);
		uint256 _burning2 = Transfers._getBalance(buybackToken1);
		require(_burning1 >= _minBurning1, "high slippage");
		require(_burning2 >= _minBurning2, "high slippage");
		_burn(buybackToken1, _burning1);
		_burn(buybackToken2, _burning2);
		lastGulpTime = now;
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

	function setRewardSplit(uint256 _newRewardBuyback1Share, uint256 _newRewardBuyback2Share) external onlyOwner nonReentrant
	{
		require(_newRewardBuyback1Share <= 1e18, "invalid rate");
		require(_newRewardBuyback2Share <= 1e18, "invalid rate");
		require(_newRewardBuyback1Share + _newRewardBuyback2Share == 1e18, "invalid split");
		uint256 _oldRewardBuyback1Share = rewardBuyback1Share;
		uint256 _oldRewardBuyback2Share = rewardBuyback2Share;
		rewardBuyback1Share = _newRewardBuyback1Share;
		rewardBuyback2Share = _newRewardBuyback2Share;
		emit ChangeRewardSplit(_oldRewardBuyback1Share, _oldRewardBuyback2Share, _newRewardBuyback1Share, _newRewardBuyback2Share);
	}

	function _capSplitAmount(uint256 _amount1, uint256 _amount2) internal view returns (uint256 _capped1, uint256 _capped2)
	{
		uint256 _limit = _calcMaxRewardTransferAmount();
		if (_amount1 > _amount2) {
			if (_amount1 > _limit) {
				_amount2 = _amount2.mul(_limit) / _amount1;
				_amount1 = _limit;
			}
		} else {
			if (_amount2 > _limit) {
				_amount1 = _amount1.mul(_limit) / _amount2;
				_amount2 = _limit;
			}
		}
		return (_amount1, _amount2);
	}

	function _burn(address _token, uint256 _amount) internal
	{
		Transfers._pushFunds(_token, FURNACE, _amount);
	}

	function _send(address _token, address _to, uint256 _amount) internal
	{
		Transfers._pushFunds(_token, _to, _amount);
	}

	function _calcMaxRewardTransferAmount() internal view returns (uint256 _maxRewardTransferAmount)
	{
		return PantherToken(rewardToken).maxTransferAmount();
	}

	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeRewardSplit(uint256 _oldRewardBuyback1Share, uint256 _oldRewardBuyback2Share, uint256 _newRewardBuyback1Share, uint256 _newRewardBuyback2Share);
}
