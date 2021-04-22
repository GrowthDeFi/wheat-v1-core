// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { IExchange } from "./IExchange.sol";

import { Transfers } from "./modules/Transfers.sol";
import { UniswapV2ExchangeAbstraction } from "./modules/UniswapV2ExchangeAbstraction.sol";
import { UniswapV2LiquidityPoolAbstraction } from "./modules/UniswapV2LiquidityPoolAbstraction.sol";

contract Exchange is IExchange
{
	address public immutable router;

	constructor (address _router) public
	{
		router = _router;
	}

	function calcConversionFromInput(address _from, address _to, uint256 _inputAmount) external view override returns (uint256 _outputAmount)
	{
		return UniswapV2ExchangeAbstraction._calcConversionFromInput(router, _from, _to, _inputAmount);
	}

	function calcConversionFromOutput(address _from, address _to, uint256 _outputAmount) external view override returns (uint256 _inputAmount)
	{
		return UniswapV2ExchangeAbstraction._calcConversionFromOutput(router, _from, _to, _outputAmount);
	}

	function calcJoinPoolFromInput(address _pool, address _token, uint256 _inputAmount) external view override returns (uint256 _outputShares)
	{
		return UniswapV2LiquidityPoolAbstraction._calcJoinPoolFromInput(_pool, _token, _inputAmount);
	}

	function convertFundsFromInput(address _from, address _to, uint256 _inputAmount, uint256 _minOutputAmount) external override returns (uint256 _outputAmount)
	{
		address _sender = msg.sender;
		Transfers._pullFunds(_from, _sender, _inputAmount);
		_outputAmount = UniswapV2ExchangeAbstraction._convertFundsFromInput(router, _from, _to, _inputAmount, _minOutputAmount);
		Transfers._pushFunds(_to, _sender, _outputAmount);
		return _outputAmount;
	}

	function convertFundsFromOutput(address _from, address _to, uint256 _outputAmount, uint256 _maxInputAmount) external override returns (uint256 _inputAmount)
	{
		address _sender = msg.sender;
		Transfers._pullFunds(_from, _sender, _maxInputAmount);
		_inputAmount = UniswapV2ExchangeAbstraction._convertFundsFromOutput(router, _from, _to, _outputAmount, _maxInputAmount);
		Transfers._pushFunds(_from, _sender, _maxInputAmount - _inputAmount);
		Transfers._pushFunds(_to, _sender, _outputAmount);
		return _inputAmount;
	}

	function joinPoolFromInput(address _pool, address _token, uint256 _inputAmount, uint256 _minOutputShares) external override returns (uint256 _outputShares)
	{
		address _sender = msg.sender;
		Transfers._pullFunds(_token, _sender, _inputAmount);
		_outputShares = UniswapV2LiquidityPoolAbstraction._joinPoolFromInput(_pool, _token, _inputAmount, _minOutputShares);
		Transfers._pushFunds(_pool, _sender, _outputShares);
		return _outputShares;
	}
}
