// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IExchange } from "./IExchange.sol";
import { WhitelistGuard } from "./WhitelistGuard.sol";

import { Transfers } from "./modules/Transfers.sol";
import { UniswapV2LiquidityPoolAbstraction } from "./modules/UniswapV2LiquidityPoolAbstraction.sol";

import { MasterChef } from "./interop/MasterChef.sol";
import { Pair } from "./interop/UniswapV2.sol";

contract PancakeSwapCompoundingStrategyToken is ERC20, ReentrancyGuard, WhitelistGuard
{
	using SafeMath for uint256;
	using LibPancakeSwapCompoundingStrategy for LibPancakeSwapCompoundingStrategy.Self;

	address public dev;
	address public treasury;
	address public collector;

	LibPancakeSwapCompoundingStrategy.Self lib;

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

	function reserveToken() external view returns (address _reserveToken)
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

	function totalReserve() public view returns (uint256 _totalReserve)
	{
		_totalReserve = lib.totalReserve();
		if (_totalReserve == uint256(-1)) return _totalReserve;
		return _totalReserve + 1; // avoids division by zero
	}

	function calcSharesFromAmount(uint256 _amount) external view returns (uint256 _shares)
	{
		(,,_shares) = _calcSharesFromAmount(_amount);
		return _shares;
	}

	function calcAmountFromShares(uint256 _shares) external view returns (uint256 _amount)
	{
		(_amount) = _calcAmountFromShares(_shares);
		return _amount;
	}

	function pendingReward() external view returns (uint256 _rewardAmount)
	{
		return lib.calcPendingReward();
	}

	function pendingPerformanceFee() external view returns (uint256 _feeAmount)
	{
		return lib.calcPerformanceFee();
	}

	function deposit(uint256 _amount) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _devAmount, uint256 _netAmount, uint256 _shares) = _calcSharesFromAmount(_amount);
		Transfers._pullFunds(lib.reserveToken, _from, _amount);
		Transfers._pushFunds(lib.reserveToken, dev, _devAmount);
		lib.deposit(_netAmount);
		_mint(_from, _shares);
	}

	function withdraw(uint256 _shares) external onlyEOAorWhitelist nonReentrant
	{
		address _from = msg.sender;
		(uint256 _amount) = _calcAmountFromShares(_shares);
		_burn(_from, _shares);
		lib.withdraw(_amount);
		Transfers._pushFunds(lib.reserveToken, _from, _amount);
	}

	function gulp() external onlyEOAorWhitelist nonReentrant
	{
		lib.gulpPerformanceFee(collector);
		lib.gulpPendingReward();
	}

	function recoverLostFunds(address _token) external onlyOwner nonReentrant
	{
		require(_token != lib.reserveToken, "invalid token");
		require(_token != lib.routingToken, "invalid token");
		require(_token != lib.rewardToken, "invalid token");
		require(_token != lib.stakeToken, "invalid token");
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

	function _calcSharesFromAmount(uint256 _amount) internal view returns (uint256 _devAmount, uint256 _netAmount, uint256 _shares)
	{
		uint256 _feeAmount = _amount.mul(lib.depositFee) / 1e18;
		_devAmount = _feeAmount;
		_netAmount = _amount - _feeAmount;
		_shares = _netAmount.mul(totalSupply()) / totalReserve();
		return (_devAmount, _netAmount, _shares);
	}

	event ChangeExchange(address _oldExchange, address _newExchange);
	event ChangeDev(address _oldDev, address _newDev);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
	event ChangeCollector(address _oldCollector, address _newCollector);
	event ChangeDepositFee(uint256 _oldDepositFee, uint256 _newDepositFee);
	event ChangePerformanceFee(uint256 _oldPerformanceFee, uint256 _newPerformanceFee);
}

library LibPancakeSwapCompoundingStrategy
{
	using SafeMath for uint256;
	using LibPancakeSwapCompoundingStrategy for LibPancakeSwapCompoundingStrategy.Self;

	uint256 constant MAXIMUM_DEPOSIT_FEE = 1e16; // 1%
	uint256 constant DEFAULT_DEPOSIT_FEE = 0e16; // 0%

	uint256 constant MAXIMUM_PERFORMANCE_FEE = 50e16; // 50%
	uint256 constant DEFAULT_PERFORMANCE_FEE = 10e16; // 10%

	struct Self {
		address masterChef;
		uint256 pid;

		address reserveToken;
		address routingToken;
		address rewardToken;
		address stakeToken;

		address exchange;

		uint256 depositFee;
		uint256 performanceFee;
	}

	function init(Self storage _self, address _masterChef, uint256 _pid, address _routingToken) public
	{
		_self._init(_masterChef, _pid, _routingToken);
	}

	function totalReserve(Self storage _self) public view returns (uint256 _totalReserve)
	{
		return _self._totalReserve();
	}

	function calcPendingReward(Self storage _self) public view returns (uint256 _rewardAmount)
	{
		return _self._calcPendingReward();
	}

	function calcPerformanceFee(Self storage _self) public view returns (uint256 _feeAmount)
	{
		return _self._calcPerformanceFee();
	}

	function deposit(Self storage _self, uint256 _amount) public
	{
		_self._deposit(_amount);
	}

	function withdraw(Self storage _self, uint256 _amount) public
	{
		_self._withdraw(_amount);
	}

	function gulpPendingReward(Self storage _self) public
	{
		_self._gulpPendingReward();
	}

	function gulpPerformanceFee(Self storage _self, address _to) public
	{
		_self._gulpPerformanceFee(_to);
	}

	function setExchange(Self storage _self, address _exchange) public
	{
		_self._setExchange(_exchange);
	}

	function setDepositFee(Self storage _self, uint256 _newDepositFee) public
	{
		_self._setDepositFee(_newDepositFee);
	}

	function setPerformanceFee(Self storage _self, uint256 _newPerformanceFee) public
	{
		_self._setPerformanceFee(_newPerformanceFee);
	}

	function _init(Self storage _self, address _masterChef, uint256 _pid, address _routingToken) internal
	{
		uint256 _poolLength = MasterChef(_masterChef).poolLength();
		require(_pid < _poolLength, "invalid pid");
		(address _reserveToken,,,) = MasterChef(_masterChef).poolInfo(_pid);
		require(_routingToken == _reserveToken || _routingToken == Pair(_reserveToken).token0() || _routingToken == Pair(_reserveToken).token1(), "invalid token");
		address _rewardToken = MasterChef(_masterChef).cake();
		address _stakeToken = MasterChef(_masterChef).syrup();
		_self.masterChef = _masterChef;
		_self.pid = _pid;
		_self.reserveToken = _reserveToken;
		_self.routingToken = _routingToken;
		_self.rewardToken = _rewardToken;
		_self.stakeToken = _stakeToken;
		_self.depositFee = DEFAULT_DEPOSIT_FEE;
		_self.performanceFee = DEFAULT_PERFORMANCE_FEE;
	}

	function _totalReserve(Self storage _self) internal view returns (uint256 _reserve)
	{
		(_reserve,) = MasterChef(_self.masterChef).userInfo(_self.pid, address(this));
		return _reserve;
	}

	function _calcPendingReward(Self storage _self) internal view returns (uint256 _rewardAmount)
	{
		require(_self.exchange != address(0), "exchange not set");
		uint256 _collectedReward = Transfers._getBalance(_self.rewardToken);
		uint256 _pendingReward = MasterChef(_self.masterChef).pendingCake(_self.pid, address(this));
		uint256 _totalReward = _collectedReward.add(_pendingReward);
		uint256 _feeReward = _totalReward.mul(_self.performanceFee) / 1e18;
		uint256 _netReward = _totalReward - _feeReward;
		uint256 _totalConverted = _netReward;
		if (_self.routingToken != _self.rewardToken) {
			_totalConverted = IExchange(_self.exchange).calcConversionFromInput(_self.rewardToken, _self.routingToken, _netReward);
		}
		uint256 _totalJoined = _totalConverted;
		if (_self.routingToken != _self.reserveToken) {
			_totalJoined = UniswapV2LiquidityPoolAbstraction._calcJoinPoolFromInput(_self.reserveToken, _self.routingToken, _totalConverted);
		}
		return _totalJoined;
	}

	function _calcPerformanceFee(Self storage _self) internal view returns (uint256 _feeReward)
	{
		uint256 _collectedReward = Transfers._getBalance(_self.rewardToken);
		uint256 _pendingReward = MasterChef(_self.masterChef).pendingCake(_self.pid, address(this));
		uint256 _totalReward = _collectedReward.add(_pendingReward);
		return _totalReward.mul(_self.performanceFee) / 1e18;
	}

	function _deposit(Self storage _self, uint256 _amount) internal
	{
		Transfers._approveFunds(_self.reserveToken, _self.masterChef, _amount);
		if (_self.pid == 0) {
			MasterChef(_self.masterChef).enterStaking(_amount);
		} else {
			MasterChef(_self.masterChef).deposit(_self.pid, _amount);
		}
	}

	function _withdraw(Self storage _self, uint256 _amount) internal
	{
		if (_self.pid == 0) {
			MasterChef(_self.masterChef).leaveStaking(_amount);
		} else {
			MasterChef(_self.masterChef).withdraw(_self.pid, _amount);
		}
	}

	function _gulpPendingReward(Self storage _self) internal
	{
		require(_self.exchange != address(0), "exchange not set");
		if (_self.routingToken != _self.rewardToken) {
			uint256 _totalReward = Transfers._getBalance(_self.rewardToken);
			Transfers._approveFunds(_self.rewardToken, _self.exchange, _totalReward);
			IExchange(_self.exchange).convertFundsFromInput(_self.rewardToken, _self.routingToken, _totalReward, 1);
		}
		if (_self.routingToken != _self.reserveToken) {
			uint256 _totalConverted = Transfers._getBalance(_self.routingToken);
			UniswapV2LiquidityPoolAbstraction._joinPoolFromInput(_self.reserveToken, _self.routingToken, _totalConverted, 1);
		}
		uint256 _totalJoined = Transfers._getBalance(_self.reserveToken);
		_self._deposit(_totalJoined);
	}

	// must be called prior to _gulpPendingReward
	function _gulpPerformanceFee(Self storage _self, address _to) internal
	{
		uint256 _pendingReward = MasterChef(_self.masterChef).pendingCake(_self.pid, address(this));
		if (_pendingReward > 0) {
			_self._withdraw(0);
		}
		uint256 _totalReward = Transfers._getBalance(_self.rewardToken);
		uint256 _feeReward = _totalReward.mul(_self.performanceFee) / 1e18;
		Transfers._pushFunds(_self.rewardToken, _to, _feeReward);
	}

	function _setExchange(Self storage _self, address _exchange) internal
	{
		_self.exchange = _exchange;
	}

	function _setDepositFee(Self storage _self, uint256 _newDepositFee) internal
	{
		require(_newDepositFee <= MAXIMUM_DEPOSIT_FEE, "invalid rate");
		_self.depositFee = _newDepositFee;
	}

	function _setPerformanceFee(Self storage _self, uint256 _newPerformanceFee) internal
	{
		require(_newPerformanceFee <= MAXIMUM_PERFORMANCE_FEE, "invalid rate");
		_self.performanceFee = _newPerformanceFee;
	}
}
