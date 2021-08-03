// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/**
 * @notice Oracle contract interface. Provides average prices as basis to avoid
 *         price manipulations.
 */
interface IOracle
{
	// view functions
	function consultLastPrice(address _pair, address _token, uint256 _amountIn) external view returns (uint256 _amountOut);
	function consultCurrentPrice(address _pair, address _token, uint256 _amountIn) external view returns (uint256 _amountOut);

	// open functions
	function activate(address _pair) external;
	function updatePrice(address _pair) external;
}
