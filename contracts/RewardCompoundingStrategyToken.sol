// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IStrategyToken } from "./IStrategyToken.sol";
import { LibRewardCompoundingStrategy } from "./LibRewardCompoundingStrategy.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

contract RewardCompoundingStrategyToken is IStrategyToken, ERC20, ReentrancyGuard, WhitelistGuard
{
	using SafeMath for uint256;
	using LibRewardCompoundingStrategy for LibRewardCompoundingStrategy.Self;

	uint256 constant DEPOSIT_FEE_COLLECTOR_SHARE = 833333333333333333; // 5/6
	uint256 constant DEPOSIT_FEE_DEV_SHARE = 166666666666666667; // 1/6

	address public dev;
	address public treasury;
	address public collector;

	LibRewardCompoundingStrategy.Self lib;

	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _masterChef, uint256 _pid, address _routingToken,
		address _dev, address _treasury, address _collector)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		lib.init(_masterChef, _pid, _routingToken);
		dev = _dev;
		treasury = _treasury;
		collector = _collector;
		_mint(address(1), 1); // avoids division by zero
	}

	function reserveToken() external view override returns (address _reserveToken)
	{
		return lib.reserveToken;
	}

	function routingToken() external view returns (address _routingToken)
	{
		return lib.routingToken;
	}

	function rewardToken() external view returns (address _rewardToken)
	{
		return lib.rewardToken;
	}

	function exchange() external view returns (address _exchange)
	{
		return lib.exchange;
	}

	function depositFee() external view returns (uint256 _depositFee)
	{
		return lib.depositFee;
	}

	function performanceFee() external view returns (uint256 _performanceFee)
	{
		return lib.performanceFee;
	}

	function totalReserve() public view override returns (uint256 _totalReserve)
	{
		_totalReserve = lib.totalReserve();
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
		return lib.calcReward();
	}

	function pendingPerformanceFee() external view returns (uint256 _feeCost)
	{
		return lib.calcPerformanceFee();
	}

	function deposit(uint256 _amount) external override onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _devAmount, uint256 _collectorAmount, uint256 _netAmount, uint256 _shares) = _calcSharesFromAmount(_amount);
		Transfers._pullFunds(lib.reserveToken, _from, _amount);
		Transfers._pushFunds(lib.reserveToken, dev, _devAmount);
		Transfers._pushFunds(lib.reserveToken, collector, _collectorAmount);
		lib.deposit(_netAmount);
		_mint(_from, _shares);
	}

	function withdraw(uint256 _shares) external override onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _amount) = _calcAmountFromShares(_shares);
		_burn(_from, _shares);
		lib.withdraw(_amount);
		Transfers._pushFunds(lib.reserveToken, _from, _amount);
	}

	function gulp() external onlyEOAorWhitelist nonReentrant
	{
		lib.gulpReward();
		lib.gulpPerformanceFee(collector);
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
	{
		require(_token != lib.reserveToken, "invalid token");
		require(_token != lib.routingToken, "invalid token");
		require(_token != lib.rewardToken, "invalid token");
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
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

	function setExchange(address _newExchange) external onlyOwner nonReentrant
	{
		address _oldExchange = lib.exchange;
		lib.setExchange(_newExchange);
		emit ChangeExchange(_oldExchange, _newExchange);
	}

	function setDepositFee(uint256 _newDepositFee) external onlyOwner nonReentrant
	{
		uint256 _oldDepositFee = lib.depositFee;
		lib.setDepositFee(_newDepositFee);
		emit ChangeDepositFee(_oldDepositFee, _newDepositFee);
	}

	function setPerformanceFee(uint256 _newPerformanceFee) external onlyOwner nonReentrant
	{
		uint256 _oldPerformanceFee = lib.performanceFee;
		lib.setPerformanceFee(_newPerformanceFee);
		emit ChangePerformanceFee(_oldPerformanceFee, _newPerformanceFee);
	}

	function _calcAmountFromShares(uint256 _shares) internal view returns (uint256 _amount)
	{
		return _shares.mul(totalReserve()) / totalSupply();
	}

	function _calcSharesFromAmount(uint256 _amount) internal view returns (uint256 _devAmount, uint256 _collectorAmount, uint256 _netAmount, uint256 _shares)
	{
		uint256 _feeAmount = _amount.mul(lib.depositFee) / 1e18;
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
