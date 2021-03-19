// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/**
 * @dev Minimal set of declarations for Uniswap V2 interoperability.
 */
interface Router01
{
	function WETH() external pure returns (address _token);

	function swapETHForExactTokens(uint256 _amountOut, address[] calldata _path, address _to, uint256 _deadline) external payable returns (uint256[] memory _amounts);
}

interface Router02 is Router01
{
}
