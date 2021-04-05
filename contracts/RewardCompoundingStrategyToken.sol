// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IStrategyToken } from "./IStrategyToken.sol";
import { LibPerformanceFee } from "./LibPerformanceFee.sol";
import { LibRewardCompoundingStrategy } from "./LibRewardCompoundingStrategy.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

contract RewardCompoundingStrategyToken is IStrategyToken, ERC20, ReentrancyGuard, WhitelistGuard
{
	using SafeMath for uint256;
	using LibPerformanceFee for LibPerformanceFee.Self;
	using LibRewardCompoundingStrategy for LibRewardCompoundingStrategy.Self;

	uint256 constant MAXIMUM_DEPOSIT_FEE = 5e16; // 5%
	uint256 constant DEFAULT_DEPOSIT_FEE = 3e16; // 3%

	uint256 constant DEPOSIT_FEE_COLLECTOR_SHARE = 833333333333333333; // 5/6
	uint256 constant DEPOSIT_FEE_DEV_SHARE = 166666666666666667; // 1/6

	address public dev;
	address public treasury;
	address public collector;

	uint256 public depositFee = DEFAULT_DEPOSIT_FEE;

	LibRewardCompoundingStrategy.Self lrcs;
	LibPerformanceFee.Self lpf;

	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _masterChef, uint256 _pid, address _routingToken,
		address _dev, address _treasury, address _collector)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		lrcs.init(_masterChef, _pid, _routingToken);
		lpf.init(lrcs.reserveToken);
		dev = _dev;
		treasury = _treasury;
		collector = _collector;
		_mint(address(1), 1); // avoids division by zero
	}

	function reserveToken() external view override returns (address _reserveToken)
	{
		return lrcs.reserveToken;
	}

	function routingToken() external view returns (address _routingToken)
	{
		return lrcs.routingToken;
	}

	function rewardToken() external view returns (address _rewardToken)
	{
		return lrcs.rewardToken;
	}

	function exchange() external view returns (address _exchange)
	{
		return lrcs.exchange;
	}

	function performanceFee() external view returns (uint256 _performanceFee)
	{
		return lpf.performanceFee;
	}

	function totalReserve() public view override returns (uint256 _totalReserve)
	{
		_totalReserve = lrcs.totalReserve();
		if (_totalReserve == uint256(-1)) return _totalReserve;
		return _totalReserve + 1; // avoids division by zero
	}

	function calcSharesFromAmount(uint256 _amount) external view override returns (uint256 _shares)
	{
		(,,,_shares) = _calcSharesFromAmount(_amount);
		return _shares;
	}

	function calcAmountFromShares(uint256 _shares) external view override returns (uint256 _amount)
	{
		(_amount) = _calcAmountFromShares(_shares);
		return _amount;
	}

	function pendingReward() external view returns (uint256 _rewardAmount)
	{
		return lrcs.calcReward();
	}

	function pendingPerformanceFee() external view returns (uint256 _feeCost)
	{
		return lpf.calcPerformanceFee();
	}

	function deposit(uint256 _amount) external override onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _devAmount, uint256 _collectorAmount, uint256 _netAmount, uint256 _shares) = _calcSharesFromAmount(_amount);
		Transfers._pullFunds(lrcs.reserveToken, _from, _amount);
		Transfers._pushFunds(lrcs.reserveToken, dev, _devAmount);
		Transfers._pushFunds(lrcs.reserveToken, collector, _collectorAmount);
		lrcs.deposit(_netAmount);
		_mint(_from, _shares);
	}

	function withdraw(uint256 _shares) external override onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _amount) = _calcAmountFromShares(_shares);
		_burn(_from, _shares);
		lrcs.withdraw(_amount);
		Transfers._pushFunds(lrcs.reserveToken, _from, _amount);
	}

	function gulp() external onlyEOAorWhitelist nonReentrant
	{
		lrcs.gulpReward();
		lpf.gulpPerformanceFee(collector);
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
	{
		require(_token != lrcs.reserveToken, "invalid token");
		require(_token != lrcs.routingToken, "invalid token");
		require(_token != lrcs.rewardToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	function setExchange(address _newExchange) external onlyOwner nonReentrant
	{
		address _oldExchange = lrcs.exchange;
		lrcs.setExchange(_newExchange);
		emit ChangeExchange(_oldExchange, _newExchange);
	}

	function setDev(address _newDev) external onlyOwner nonReentrant
	{
		require(_newDev != address(0), "invalid address");
		address _oldDev = dev;
		dev = _newDev;
		emit ChangeDev(_oldDev, _newDev);
	}

	function setTreasury(address _newTreasury) external onlyOwner nonReentrant
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	function setCollector(address _newCollector) external onlyOwner nonReentrant
	{
		require(_newCollector != address(0), "invalid address");
		address _oldCollector = collector;
		collector = _newCollector;
		emit ChangeCollector(_oldCollector, _newCollector);
	}

	function setDepositFee(uint256 _newDepositFee) external onlyOwner nonReentrant
	{
		require(_newDepositFee <= MAXIMUM_DEPOSIT_FEE, "invalid rate");
		uint256 _oldDepositFee = depositFee;
		depositFee = _newDepositFee;
		emit ChangeDepositFee(_oldDepositFee, _newDepositFee);
	}

	function setPerformanceFee(uint256 _newPerformanceFee) external onlyOwner nonReentrant
	{
		uint256 _oldPerformanceFee = lpf.performanceFee;
		lpf.setPerformanceFee(_newPerformanceFee);
		emit ChangePerformanceFee(_oldPerformanceFee, _newPerformanceFee);
	}

	function _calcAmountFromShares(uint256 _shares) internal view returns (uint256 _amount)
	{
		return _shares.mul(totalReserve()) / totalSupply();
	}

	function _calcSharesFromAmount(uint256 _amount) internal view returns (uint256 _devAmount, uint256 _collectorAmount, uint256 _netAmount, uint256 _shares)
	{
		uint256 _feeAmount = _amount.mul(depositFee) / 1e18;
		_devAmount = (_feeAmount * DEPOSIT_FEE_DEV_SHARE) / 1e18;
		_collectorAmount = _feeAmount - _devAmount;
		_netAmount = _amount - _feeAmount;
		_shares = _netAmount.mul(totalSupply()) / totalReserve();
		return (_devAmount, _collectorAmount, _netAmount, _shares);
	}

	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeDev(address _oldDev, address _newDev);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeDepositFee(uint256 _oldDepositFee, uint256 _newDepositFee);
	event ChangePerformanceFee(uint256 _oldPerformanceFee, uint256 _newPerformanceFee);
}
