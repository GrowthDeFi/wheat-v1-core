// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/**
 * @notice Oracle contract interface. Facilitates the conversion between assets
 *         including liquidity pool shares.
 */
interface IOracle
{
	// view functions
	//function calcMinimumFromInput(address _from, address _to, uint256 _inputAmount) external view returns (uint256 _minOutputAmount);
	//function calcMinimumFromOutput(address _from, address _to, uint256 _outputAmount) external view returns (uint256 _maxInputAmount);
}
