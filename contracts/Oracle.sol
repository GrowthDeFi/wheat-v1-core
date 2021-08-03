// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { FixedPoint } from "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import { UniswapV2OracleLibrary } from "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";

import { IOracle } from "./IOracle.sol";

contract Oracle is IOracle, Ownable
{
	using FixedPoint for FixedPoint.uq112x112;
	using FixedPoint for FixedPoint.uq144x112;

	struct PairInfo {
		bool active;
		uint256 price0CumulativeLast;
		uint256 price1CumulativeLast;
		uint32 blockTimestampLast;
		FixedPoint.uq112x112 price0Average;
		FixedPoint.uq112x112 price1Average;
		uint256 minimumInterval;
	}

	uint256 constant DEFAULT_MINIMUM_INTERVAL = 24 hours;

	mapping (address => PairInfo) private pairInfo;

	function activate(address _pair) external
	{
		PairInfo storage _pairInfo = pairInfo[_pair];
		require(!_pairInfo.active, "already active");

		uint256 _price0CumulativeLast = IUniswapV2Pair(_pair).price0CumulativeLast();
		uint256 _price1CumulativeLast = IUniswapV2Pair(_pair).price1CumulativeLast();
		(uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = IUniswapV2Pair(_pair).getReserves();
		require(_reserve0 > 0 && _reserve1 > 0, "no reserves"); // ensure that there's liquidity in the pair

		FixedPoint.uq112x112 memory _price0Average = FixedPoint.fraction(_reserve1, _reserve0);
		FixedPoint.uq112x112 memory _price1Average = FixedPoint.fraction(_reserve0, _reserve1);

		_pairInfo.active = true;
		_pairInfo.price0CumulativeLast = _price0CumulativeLast;
		_pairInfo.price1CumulativeLast = _price1CumulativeLast;
		_pairInfo.blockTimestampLast = _blockTimestampLast;
		_pairInfo.price0Average = _price0Average;
		_pairInfo.price1Average = _price1Average;
		_pairInfo.minimumInterval = DEFAULT_MINIMUM_INTERVAL;
	}

	function consultLastPrice(address _pair, address _token, uint256 _amountIn) public view returns (uint256 _amountOut)
	{
		address _token0 = IUniswapV2Pair(_pair).token0();
		address _token1 = IUniswapV2Pair(_pair).token1();
		bool _use0 = _token == _token0;
		bool _use1 = _token == _token1;
		require(_use0 || _use1, "invalid token");
		PairInfo storage _pairInfo = pairInfo[_pair];
		require(_pairInfo.active, "not active");
		FixedPoint.uq112x112 memory _priceAverage = _use0 ? _pairInfo.price0Average : _pairInfo.price1Average;
		return _priceAverage.mul(_amountIn).decode144();
	}

	function consultCurrentPrice(address _pair, address _token, uint256 _amountIn) public view returns (uint256 _amountOut)
	{
		address _token0 = IUniswapV2Pair(_pair).token0();
		address _token1 = IUniswapV2Pair(_pair).token1();
		bool _use0 = _token == _token0;
		bool _use1 = _token == _token1;
		require(_use0 || _use1, "invalid token");
		(,,,, FixedPoint.uq112x112 memory _price0Average, FixedPoint.uq112x112 memory _price1Average) = _estimatePrice(_pair);
		FixedPoint.uq112x112 memory _priceAverage = _use0 ? _price0Average : _price1Average;
		return _priceAverage.mul(_amountIn).decode144();
	}

	function updatePrice(address _pair) external
	{
		PairInfo storage _pairInfo = pairInfo[_pair];
		uint32 _timeElapsed;
		(_pairInfo.price0CumulativeLast, _pairInfo.price1CumulativeLast, _pairInfo.blockTimestampLast, _timeElapsed, _pairInfo.price0Average, _pairInfo.price1Average) = _estimatePrice(_pair);
		require(_timeElapsed >= _pairInfo.minimumInterval, "minimum interval not elapsed"); // ensure that at least one full interval has passed since the last update
	}

	function setMinimumInterval(address _pair, uint256 _newMinimumInterval) external onlyOwner
	{
		require(_newMinimumInterval > 0, "invalid interval");
		PairInfo storage _pairInfo = pairInfo[_pair];
		uint256 _oldMinimumInterval = _pairInfo.minimumInterval;
		_pairInfo.minimumInterval = _newMinimumInterval;
		emit ChangeMinimumInterval(_pair, _oldMinimumInterval, _newMinimumInterval);
	}

	function _estimatePrice(address _pair) internal view returns (uint256 _price0Cumulative, uint256 _price1Cumulative, uint32 _blockTimestamp, uint32 _timeElapsed, FixedPoint.uq112x112 memory _price0Average, FixedPoint.uq112x112 memory _price1Average)
	{
		PairInfo storage _pairInfo = pairInfo[_pair];
		require(_pairInfo.active, "not active");
		uint256 _price0CumulativeLast = _pairInfo.price0CumulativeLast;
		uint256 _price1CumulativeLast = _pairInfo.price1CumulativeLast;
		uint32 _blockTimestampLast = _pairInfo.blockTimestampLast;
		FixedPoint.uq112x112 memory _price0AverageLast = _pairInfo.price0Average;
		FixedPoint.uq112x112 memory _price1AverageLast = _pairInfo.price1Average;

		// cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
		(_price0Cumulative, _price1Cumulative, _blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(_pair);
		_timeElapsed = _blockTimestamp - _blockTimestampLast; // overflow is desired
		_price0Average = _price0AverageLast;
		_price1Average = _price1AverageLast;
		if (_timeElapsed > 0) {
			_price0Average = FixedPoint.uq112x112(uint224((_price0Cumulative - _price0CumulativeLast) / _timeElapsed)); // overflow is desired, casting never truncates
			_price1Average = FixedPoint.uq112x112(uint224((_price1Cumulative - _price1CumulativeLast) / _timeElapsed)); // overflow is desired, casting never truncates
		}
		return (_price0Cumulative, _price1Cumulative, _blockTimestamp, _timeElapsed, _price0Average, _price1Average);
	}

	// events emitted by this contract
	event ChangeMinimumInterval(address indexed _pair, uint256 _oldMinimumInterval, uint256 _newMinimumInterval);
}
