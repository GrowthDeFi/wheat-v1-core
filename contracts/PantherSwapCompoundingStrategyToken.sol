// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";

import { PantherToken, PantherMasterChef } from "./interop/PantherSwap.sol";
import { Pair } from "./interop/UniswapV2.sol";

contract PantherSwapCompoundingStrategyToken is ERC20, ReentrancyGuard, WhitelistGuard
{
	using SafeMath for uint256;

	uint256 constant MAXIMUM_PERFORMANCE_FEE = 100e16; // 100%
	uint256 constant DEFAULT_PERFORMANCE_FEE = 50e16; // 50%

	address private immutable masterChef;
	uint256 private immutable pid;

	address public immutable rewardToken;
	address public immutable routingToken;
	address public immutable reserveToken;

	address public dev;
	address public treasury;
	address public buyback;

	address public exchange;

	uint256 public performanceFee = DEFAULT_PERFORMANCE_FEE;

	uint256 public lastGulpTime;

	constructor (string memory _name, string memory _symbol, uint8 _decimals,
		address _masterChef, uint256 _pid, address _routingToken,
		address _dev, address _treasury, address _buyback, address _exchange)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		(address _reserveToken, address _rewardToken) = _getTokens(_masterChef, _pid);
		require(_routingToken == _reserveToken || _routingToken == Pair(_reserveToken).token0() || _routingToken == Pair(_reserveToken).token1(), "invalid token");
		masterChef = _masterChef;
		pid = _pid;
		rewardToken = _rewardToken;
		routingToken = _routingToken;
		reserveToken = _reserveToken;
		dev = _dev;
		treasury = _treasury;
		buyback = _buyback;
		exchange = _exchange;
		_mint(address(1), 1); // avoids division by zero
	}

	function totalReserve() public view returns (uint256 _totalReserve)
	{
		_totalReserve = _getReserveAmount();
		if (_totalReserve == uint256(-1)) return _totalReserve;
		return _totalReserve + 1; // avoids division by zero
	}

	function calcSharesFromAmount(uint256 _amount) external view returns (uint256 _shares)
	{
		(_shares,,) = _calcSharesFromAmount(_amount);
		return _shares;
	}

	function calcAmountFromShares(uint256 _shares) external view returns (uint256 _amount)
	{
		(,,_amount) = _calcAmountFromShares(_shares);
		return _amount;
	}

	function pendingPerformanceFee() external view returns (uint256 _feeReward)
	{
		uint256 _pendingReward = _getPendingReward();
		uint256 _balanceReward = Transfers._getBalance(rewardToken);
		uint256 _totalReward = _pendingReward.add(_balanceReward);
		_feeReward = _totalReward.mul(performanceFee) / 1e18;
		return _feeReward;
	}

	function pendingReward() external view returns (uint256 _rewardAmount)
	{
		uint256 _pendingReward = _getPendingReward();
		uint256 _balanceReward = Transfers._getBalance(rewardToken);
		uint256 _totalReward = _pendingReward.add(_balanceReward);
		(uint256 _feeReward, uint256 _retainedReward) = _capFeeRewardAmount(_totalReward.mul(performanceFee) / 1e18);
		uint256 _netReward = _totalReward - _feeReward;
		uint256 _totalRouting = _netReward;
		if (rewardToken != routingToken) {
			require(exchange != address(0), "exchange not set");
			_netReward = _capTransferRewardAmount(rewardToken, _netReward, _retainedReward);
			_totalRouting = IExchange(exchange).calcConversionFromInput(rewardToken, routingToken, _netReward);
		}
		uint256 _totalBalance = _totalRouting;
		if (routingToken != reserveToken) {
			require(exchange != address(0), "exchange not set");
			_totalRouting = _capTransferRewardAmount(routingToken, _totalRouting, _retainedReward);
			_totalBalance = IExchange(exchange).calcJoinPoolFromInput(reserveToken, routingToken, _totalRouting);
		}
		_totalBalance = _capTransferRewardAmount(reserveToken, _totalBalance, _retainedReward);
		return _totalBalance;
	}

	function deposit(uint256 _amount) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _shares, uint256 _depositAmount,) = _calcSharesFromAmount(_amount);
		Transfers._pullFunds(reserveToken, _from, _amount);
		_deposit(_depositAmount);
		_mint(_from, _shares);
	}

	function withdraw(uint256 _shares) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _amount, uint256 _withdrawalAmount,) = _calcAmountFromShares(_shares);
		_burn(_from, _shares);
		_withdraw(_amount);
		Transfers._pushFunds(reserveToken, _from, _withdrawalAmount);
	}

	function gulp(uint256 _minRewardAmount) external onlyEOAorWhitelist nonReentrant
	{
		uint256 _pendingReward = _getPendingReward();
		if (_pendingReward > 0) {
			_withdraw(0);
		}
		uint256 __totalReward = Transfers._getBalance(rewardToken);
		(uint256 _feeReward, uint256 _retainedReward) = _capFeeRewardAmount(__totalReward.mul(performanceFee) / 1e18);
		Transfers._pushFunds(rewardToken, buyback, _feeReward);
		if (rewardToken != routingToken) {
			require(exchange != address(0), "exchange not set");
			uint256 _totalReward = Transfers._getBalance(rewardToken);
			_totalReward = _capTransferRewardAmount(rewardToken, _totalReward, _retainedReward);
			Transfers._approveFunds(rewardToken, exchange, _totalReward);
			IExchange(exchange).convertFundsFromInput(rewardToken, routingToken, _totalReward, 1);
		}
		if (routingToken != reserveToken) {
			require(exchange != address(0), "exchange not set");
			uint256 _totalRouting = Transfers._getBalance(routingToken);
			_totalRouting = _capTransferRewardAmount(routingToken, _totalRouting, _retainedReward);
			Transfers._approveFunds(routingToken, exchange, _totalRouting);
			IExchange(exchange).joinPoolFromInput(reserveToken, routingToken, _totalRouting, 1);
		}
		uint256 _totalBalance = Transfers._getBalance(reserveToken);
		_totalBalance = _capTransferRewardAmount(reserveToken, _totalBalance, _retainedReward);
		require(_totalBalance >= _minRewardAmount, "high slippage");
		_deposit(_totalBalance);
		lastGulpTime = now;
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
	{
		require(_token != reserveToken, "invalid token");
		require(_token != routingToken, "invalid token");
		require(_token != rewardToken, "invalid token");
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

	function setBuyback(address _newBuyback) external onlyOwner nonReentrant
	{
		require(_newBuyback != address(0), "invalid address");
		address _oldBuyback = buyback;
		buyback = _newBuyback;
		emit ChangeBuyback(_oldBuyback, _newBuyback);
	}

	function setExchange(address _newExchange) external onlyOwner nonReentrant
	{
		address _oldExchange = exchange;
		exchange = _newExchange;
		emit ChangeExchange(_oldExchange, _newExchange);
	}

	function setPerformanceFee(uint256 _newPerformanceFee) external onlyOwner nonReentrant
	{
		require(_newPerformanceFee <= MAXIMUM_PERFORMANCE_FEE, "invalid rate");
		uint256 _oldPerformanceFee = performanceFee;
		performanceFee = _newPerformanceFee;
		emit ChangePerformanceFee(_oldPerformanceFee, _newPerformanceFee);
	}

	function _calcSharesFromAmount(uint256 _amount) internal view returns (uint256 _shares, uint256 _depositAmount, uint256 _netAmount)
	{
		if (reserveToken == rewardToken) {
			_depositAmount = _calcTaxFreeRewardAmount(_amount);
			_netAmount = _calcNetDepositAmount(_calcTaxFreeRewardAmount(_depositAmount));
		} else {
			_depositAmount = _amount;
			_netAmount = _calcNetDepositAmount(_depositAmount);
		}
		_shares = _netAmount.mul(totalSupply()) / totalReserve();
		return (_shares, _depositAmount, _netAmount);
	}

	function _calcAmountFromShares(uint256 _shares) internal view returns (uint256 _amount, uint256 _withdrawalAmount, uint256 _netAmount)
	{
		_amount = _shares.mul(totalReserve()) / totalSupply();
		if (reserveToken == rewardToken) {
			_withdrawalAmount = _calcTaxFreeRewardAmount(_amount);
			_netAmount = _calcTaxFreeRewardAmount(_withdrawalAmount);
		} else {
			_withdrawalAmount = _amount;
			_netAmount = _withdrawalAmount;
		}
		return (_amount, _withdrawalAmount, _netAmount);
	}

	function _capFeeRewardAmount(uint256 _amount) internal view returns (uint256 _capped, uint256 _retained)
	{
		_retained = 0;
		uint256 _limit = _calcMaxRewardTransferAmount();
		if (_amount > _limit) {
			_amount = _limit;
			_retained = _amount.sub(_limit);
		}
		return (_amount, _retained);
	}

	function _capTransferRewardAmount(address _token, uint256 _amount, uint256 _retained) internal view returns (uint256 _capped)
	{
		if (_token == rewardToken) {
			_amount = _amount.sub(_retained);
			uint256 _limit = _calcMaxRewardTransferAmount();
			if (_amount > _limit) {
				_amount = _limit;
			}
		}
		return _amount;
	}

	function _getTokens(address _masterChef, uint256 _pid) internal view returns (address _reserveToken, address _rewardToken)
	{
		uint256 _poolLength = PantherMasterChef(_masterChef).poolLength();
		require(_pid < _poolLength, "invalid pid");
		(_reserveToken,,,,,) = PantherMasterChef(_masterChef).poolInfo(_pid);
		_rewardToken = PantherMasterChef(_masterChef).panther();
		return (_reserveToken, _rewardToken);
	}

	function _getPendingReward() internal view returns (uint256 _pendingReward)
	{
		if (!PantherMasterChef(masterChef).canHarvest(pid, address(this))) return 0;
		return PantherMasterChef(masterChef).pendingPanther(pid, address(this));
	}

	function _getReserveAmount() internal view returns (uint256 _reserveAmount)
	{
		(_reserveAmount,,,) = PantherMasterChef(masterChef).userInfo(pid, address(this));
		return _reserveAmount;
	}

	function _calcNetDepositAmount(uint256 _amount) internal view returns (uint256 _netAmount)
	{
		(,,,,uint16 _depositFeeBP,) = PantherMasterChef(masterChef).poolInfo(pid);
		uint256 _fee = _amount.mul(_depositFeeBP).div(10000);
		_netAmount = _amount.sub(_fee);
		return _netAmount;
	}

	function _calcMaxRewardTransferAmount() internal view returns (uint256 _maxRewardTransferAmount)
	{
		return PantherToken(rewardToken).maxTransferAmount();
	}

	function _calcTaxFreeRewardAmount(uint256 _amount) internal view returns (uint256 _netAmount)
	{
		uint16 _rate = PantherToken(rewardToken).transferTaxRate();
		uint256 _transferTax = _amount.mul(_rate).div(10000);
		_netAmount = _amount.sub(_transferTax);
		return _netAmount;
	}

	function _deposit(uint256 _amount) internal
	{
		Transfers._approveFunds(reserveToken, masterChef, _amount);
		PantherMasterChef(masterChef).deposit(pid, _amount, dev);
	}

	function _withdraw(uint256 _amount) internal
	{
		PantherMasterChef(masterChef).withdraw(pid, _amount);
	}

	event ChangeDev(address _oldDev, address _newDev);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeBuyback(address _oldBuyback, address _newBuyback);
	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangePerformanceFee(uint256 _oldPerformanceFee, uint256 _newPerformanceFee);
}
