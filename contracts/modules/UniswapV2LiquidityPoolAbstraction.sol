// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { Math } from "./Math.sol";
import { Transfers } from "./Transfers.sol";

import { Pair, Router02 } from "../interop/UniswapV2.sol";

/**
 * @dev This library provides functionality to facilitate adding/removing
 * single-asset liquidity to/from a Uniswap V2 pool.
 */
library UniswapV2LiquidityPoolAbstraction
{
	using SafeMath for uint256;

	function _calcJoinPoolFromInput(address _router, address _pair, address _token, uint256 _amount) internal view returns (uint256 _shares)
	{
		if (_amount == 0) return 0;
		address _token0 = Pair(_pair).token0();
		address _token1 = Pair(_pair).token1();
		require(_token == _token0 || _token == _token1, "invalid token");
		(uint256 _reserve0, uint256 _reserve1,) = Pair(_pair).getReserves();
		uint256 _balance = _token == _token0 ? _reserve0 : _reserve1;
		uint256 _otherBalance = _token == _token0 ? _reserve1 : _reserve0;
		uint256 _totalSupply = Pair(_pair).totalSupply();
		uint256 _swapAmount = _calcSwapOutputFromInput(_balance, _amount);
		if (_swapAmount == 0) _swapAmount = _amount / 2;
		uint256 _leftAmount = _amount.sub(_swapAmount);
		uint256 _otherAmount = Router02(_router).getAmountOut(_swapAmount, _balance, _otherBalance);
		_shares = Math._min(_totalSupply.mul(_leftAmount) / _balance.add(_swapAmount), _totalSupply.mul(_otherAmount) / _otherBalance.sub(_otherAmount));
		return _shares;
	}

	function _calcExitPoolFromInput(address _router, address _pair, address _token, uint256 _shares) internal view returns (uint256 _amount)
	{
		if (_shares == 0) return 0;
		address _token0 = Pair(_pair).token0();
		address _token1 = Pair(_pair).token1();
		require(_token == _token0 || _token == _token1, "invalid token");
		(uint256 _reserve0, uint256 _reserve1,) = Pair(_pair).getReserves();
		uint256 _balance = _token == _token0 ? _reserve0 : _reserve1;
		uint256 _otherBalance = _token == _token0 ? _reserve1 : _reserve0;
		uint256 _totalSupply = Pair(_pair).totalSupply();
		uint256 _baseAmount = _balance.mul(_shares) / _totalSupply;
		uint256 _swapAmount = _otherBalance.mul(_shares) / _totalSupply;
		uint256 _additionalAmount = Router02(_router).getAmountOut(_swapAmount, _otherBalance.sub(_swapAmount), _balance.sub(_baseAmount));
		_amount = _baseAmount.add(_additionalAmount);
		return _amount;
	}

	function _joinPoolFromInput(address _router, address _pair, address _token, uint256 _amount, uint256 _minShares) internal returns (uint256 _shares)
	{
		if (_amount == 0) return 0;
		address _token0 = Pair(_pair).token0();
		address _token1 = Pair(_pair).token1();
		require(_token == _token0 || _token == _token1, "invalid token");
		address _otherToken = _token == _token0 ? _token1 : _token0;
		(uint256 _reserve0, uint256 _reserve1,) = Pair(_pair).getReserves();
		uint256 _swapAmount = _calcSwapOutputFromInput(_token == _token0 ? _reserve0 : _reserve1, _amount);
		if (_swapAmount == 0) _swapAmount = _amount / 2;
		uint256 _leftAmount = _amount.sub(_swapAmount);
		Transfers._approveFunds(_token, _router, _amount);
		uint256 _otherAmount;
		{
			address[] memory _path = new address[](2);
			_path[0] = _token;
			_path[1] = _otherToken;
			uint256 _oldBalance = Transfers._getBalance(_otherToken);
			Router02(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(_swapAmount, 1, _path, address(this), uint256(-1));
			uint256 _newBalance = Transfers._getBalance(_otherToken);
			assert(_newBalance >= _oldBalance);
			_otherAmount = _newBalance - _oldBalance;
		}
		Transfers._approveFunds(_otherToken, _router, _otherAmount);
		(,,_shares) = Router02(_router).addLiquidity(_token, _otherToken, _leftAmount, _otherAmount, 1, 1, address(this), uint256(-1));
		require(_shares >= _minShares, "high slippage");
		return _shares;
	}

	function _exitPoolFromInput(address _router, address _pair, address _token, uint256 _shares, uint256 _minAmount) internal returns (uint256 _amount)
	{
		if (_shares == 0) return 0;
		address _token0 = Pair(_pair).token0();
		address _token1 = Pair(_pair).token1();
		require(_token == _token0 || _token == _token1, "invalid token");
		address _otherToken = _token == _token0 ? _token1 : _token0;
		Transfers._approveFunds(_pair, _router, _shares);
		(uint256 _baseAmount, uint256 _swapAmount) = Router02(_router).removeLiquidity(_token, _otherToken, _shares, 1, 1, address(this), uint256(-1));
		Transfers._approveFunds(_otherToken, _router, _swapAmount);
		uint256 _additionalAmount;
		{
			address[] memory _path = new address[](2);
			_path[0] = _otherToken;
			_path[1] = _token;
			uint256 _oldBalance = Transfers._getBalance(_token);
			Router02(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(_swapAmount, 1, _path, address(this), uint256(-1));
			uint256 _newBalance = Transfers._getBalance(_token);
			assert(_newBalance >= _oldBalance);
			_additionalAmount = _newBalance - _oldBalance;
		}
		_amount = _baseAmount.add(_additionalAmount);
		require(_amount >= _minAmount, "high slippage");
		return _amount;
	}

	function _calcSwapOutputFromInput(uint256 _reserveAmount, uint256 _inputAmount) private pure returns (uint256 _outputAmount)
	{
		return Math._sqrt(_reserveAmount.mul(_inputAmount.mul(3988000).add(_reserveAmount.mul(3988009)))).sub(_reserveAmount.mul(1997)) / 1994;
	}
}
