// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { IExchange } from "./IExchange.sol";
import { IOracle } from "./IOracle.sol";
import { DelayedActionGuard } from "./DelayedActionGuard.sol";

import { Math } from "./modules/Math.sol";
import { Transfers } from "./modules/Transfers.sol";
import { UniswapV2ExchangeAbstraction } from "./modules/UniswapV2ExchangeAbstraction.sol";
import { UniswapV2LiquidityPoolAbstraction } from "./modules/UniswapV2LiquidityPoolAbstraction.sol";

import { Factory, Router02 } from "./interop/UniswapV2.sol";

/**
 * @notice This contract provides a helper exchange abstraction to be used by other
 *         contracts, so that it can be replaced to accomodate routing changes.
 */
contract Exchange is IExchange, ReentrancyGuard, DelayedActionGuard
{
	using SafeMath for uint256;

	address public router;
	address public oracle;
	address public treasury;

	/**
	 * @dev Constructor for this exchange contract.
	 * @param _router The Uniswap V2 compatible router address to be used for operations.
	 * @param _treasury The treasury address used to recover lost funds.
	 */
	constructor (address _router, address _oracle, address _treasury) public
	{
		router = _router;
		oracle = _oracle;
		treasury = _treasury;
	}

	/**
	 * @notice Calculates how much output to be received from the given input
	 *         when converting between two assets.
	 * @param _from The input asset address.
	 * @param _to The output asset address.
	 * @param _inputAmount The input asset amount to be provided.
	 * @return _outputAmount The output asset amount to be received.
	 */
	function calcConversionFromInput(address _from, address _to, uint256 _inputAmount) external view override returns (uint256 _outputAmount)
	{
		return UniswapV2ExchangeAbstraction._calcConversionFromInput(router, _from, _to, _inputAmount);
	}

	/**
	 * @notice Calculates how much input to be received the given the output
	 *         when converting between two assets.
	 * @param _from The input asset address.
	 * @param _to The output asset address.
	 * @param _outputAmount The output asset amount to be received.
	 * @return _inputAmount The input asset amount to be provided.
	 */
	function calcConversionFromOutput(address _from, address _to, uint256 _outputAmount) external view override returns (uint256 _inputAmount)
	{
		return UniswapV2ExchangeAbstraction._calcConversionFromOutput(router, _from, _to, _outputAmount);
	}

	/**
	 * @dev Estimates the number of LP shares to be received by a single
	 *      asset deposit into a liquidity pool.
	 * @param _pool The liquidity pool address.
	 * @param _token The ERC-20 token for the asset being deposited.
	 * @param _inputAmount The amount to be deposited.
	 * @return _outputShares The expected number of LP shares to be received.
	 */
	function calcJoinPoolFromInput(address _pool, address _token, uint256 _inputAmount) external view override returns (uint256 _outputShares)
	{
		return UniswapV2LiquidityPoolAbstraction._calcJoinPoolFromInput(router, _pool, _token, _inputAmount);
	}

	/**
	 * @notice Convert funds between two assets given the exact input amount.
	 * @param _from The input asset address.
	 * @param _to The output asset address.
	 * @param _inputAmount The input asset amount to be provided.
	 * @param _minOutputAmount The output asset minimum amount to be received.
	 * @return _outputAmount The output asset amount received.
	 */
	function convertFundsFromInput(address _from, address _to, uint256 _inputAmount, uint256 _minOutputAmount) external override nonReentrant returns (uint256 _outputAmount)
	{
		address _sender = msg.sender;
		Transfers._pullFunds(_from, _sender, _inputAmount);
		_inputAmount = Math._min(_inputAmount, Transfers._getBalance(_from)); // deals with potential transfer tax
		_outputAmount = UniswapV2ExchangeAbstraction._convertFundsFromInput(router, _from, _to, _inputAmount, _minOutputAmount);
		_outputAmount = Math._min(_outputAmount, Transfers._getBalance(_to)); // deals with potential transfer tax
		Transfers._pushFunds(_to, _sender, _outputAmount);
		return _outputAmount;
	}

	/**
	 * @notice Convert funds between two assets given the exact output amount.
	 * @param _from The input asset address.
	 * @param _to The output asset address.
	 * @param _outputAmount The output asset amount to be received.
	 * @param _maxInputAmount The input asset maximum amount to be provided.
	 * @return _inputAmount The input asset amount provided.
	 */
	function convertFundsFromOutput(address _from, address _to, uint256 _outputAmount, uint256 _maxInputAmount) external override nonReentrant returns (uint256 _inputAmount)
	{
		address _sender = msg.sender;
		Transfers._pullFunds(_from, _sender, _maxInputAmount);
		_maxInputAmount = Math._min(_maxInputAmount, Transfers._getBalance(_from)); // deals with potential transfer tax
		_inputAmount = UniswapV2ExchangeAbstraction._convertFundsFromOutput(router, _from, _to, _outputAmount, _maxInputAmount);
		uint256 _refundAmount = _maxInputAmount - _inputAmount;
		_refundAmount = Math._min(_refundAmount, Transfers._getBalance(_from)); // deals with potential transfer tax
		Transfers._pushFunds(_from, _sender, _refundAmount);
		_outputAmount = Math._min(_outputAmount, Transfers._getBalance(_to)); // deals with potential transfer tax
		Transfers._pushFunds(_to, _sender, _outputAmount);
		return _inputAmount;
	}

	/**
	 * @dev Deposits a single asset into a liquidity pool.
	 * @param _pool The liquidity pool address.
	 * @param _token The ERC-20 token for the asset being deposited.
	 * @param _inputAmount The amount to be deposited.
	 * @param _minOutputShares The minimum number of LP shares to be received.
	 * @return _outputShares The actual number of LP shares received.
	 */
	function joinPoolFromInput(address _pool, address _token, uint256 _inputAmount, uint256 _minOutputShares) external override nonReentrant returns (uint256 _outputShares)
	{
		address _sender = msg.sender;
		Transfers._pullFunds(_token, _sender, _inputAmount);
		_inputAmount = Math._min(_inputAmount, Transfers._getBalance(_token)); // deals with potential transfer tax
		_outputShares = UniswapV2LiquidityPoolAbstraction._joinPoolFromInput(router, _pool, _token, _inputAmount, _minOutputShares);
		_outputShares = Math._min(_outputShares, Transfers._getBalance(_pool)); // deals with potential transfer tax
		Transfers._pushFunds(_pool, _sender, _outputShares);
		return _outputShares;
	}

	function oracleAveragePriceFactorFromInput(address _from, address _to, uint256 _inputAmount) external override returns (uint256 _factor)
	{
		address _WBNB = Router02(router).WETH();
		address _factory = Router02(router).factory();
		address[] memory _path = UniswapV2ExchangeAbstraction._buildPath(_from, _WBNB, _to);
		_factor = 1e18;
		uint256 _amount = _inputAmount;
		for (uint256 _i = 1; _i < _path.length; _i++) {
			address _tokenA = _path[_i - 1];
			address _tokenB = _path[_i];
			address _pool = Factory(_factory).getPair(_tokenA, _tokenB);
			IOracle(oracle).updateAveragePrice(_pool);
			uint256 _averageOutputAmount = IOracle(oracle).consultAveragePrice(_pool, _tokenA, _amount);
			uint256 _currentOutputAmount = IOracle(oracle).consultCurrentPrice(_pool, _tokenA, _amount);
			_factor = _currentOutputAmount.mul(_factor) / _averageOutputAmount;
			_amount = _currentOutputAmount;
		}
		return _factor;
	}

	function oraclePoolAveragePriceFactorFromInput(address _pool, address _token, uint256 _inputAmount) external override returns (uint256 _factor)
	{
		IOracle(oracle).updateAveragePrice(_pool);
		uint256 _averageOutputAmount = IOracle(oracle).consultAveragePrice(_pool, _token, _inputAmount);
		uint256 _currentOutputAmount = IOracle(oracle).consultCurrentPrice(_pool, _token, _inputAmount);
		_factor = _currentOutputAmount.mul(1e18) / _averageOutputAmount;
		return _factor;
	}

	/**
	 * @notice Allows the recovery of tokens sent by mistake to this
	 *         contract, excluding tokens relevant to its operations.
	 *         The full balance is sent to the treasury address.
	 *         This is a privileged function.
	 * @param _token The address of the token to be recovered.
	 */
	function recoverLostFunds(address _token) external onlyOwner nonReentrant
		delayed(this.recoverLostFunds.selector, keccak256(abi.encode(_token)))
	{
		uint256 _balance = Transfers._getBalance(_token);
		Transfers._pushFunds(_token, treasury, _balance);
	}

	/**
	 * @notice Updates the Uniswap V2 compatible router address.
	 *         This is a privileged function.
	 * @param _newRouter The new router address.
	 */
	function setRouter(address _newRouter) external onlyOwner
		delayed(this.setRouter.selector, keccak256(abi.encode(_newRouter)))
	{
		require(_newRouter != address(0), "invalid address");
		address _oldRouter = router;
		router = _newRouter;
		emit ChangeRouter(_oldRouter, _newRouter);
	}

	/**
	 * @notice Updates the Uniswap V2 compatible oracle address.
	 *         This is a privileged function.
	 * @param _newOracle The new oracle address.
	 */
	function setOracle(address _newOracle) external onlyOwner
		delayed(this.setOracle.selector, keccak256(abi.encode(_newOracle)))
	{
		require(_newOracle != address(0), "invalid address");
		address _oldOracle = oracle;
		oracle = _newOracle;
		emit ChangeOracle(_oldOracle, _newOracle);
	}

	/**
	 * @notice Updates the treasury address used to recover lost funds.
	 *         This is a privileged function.
	 * @param _newTreasury The new treasury address.
	 */
	function setTreasury(address _newTreasury) external onlyOwner
		delayed(this.setTreasury.selector, keccak256(abi.encode(_newTreasury)))
	{
		require(_newTreasury != address(0), "invalid address");
		address _oldTreasury = treasury;
		treasury = _newTreasury;
		emit ChangeTreasury(_oldTreasury, _newTreasury);
	}

	// events emitted by this contract
	event ChangeRouter(address _oldRouter, address _newRouter);
	event ChangeOracle(address _oldOracle, address _newOracle);
	event ChangeTreasury(address _oldTreasury, address _newTreasury);
}
