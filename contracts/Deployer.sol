// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { $ } from "./network/$.sol";

contract Deployer is Ownable
{
	bool public deployed = false;

	constructor () public
	{
		require($.NETWORK == $.network(), "wrong network");
	}

	function deploy() external onlyOwner
	{
		require(!deployed, "deploy unavailable");

		// contract = LibDeployer1.publishContract();

		// transfer ownerships
		// Ownable(contract).transferOwnership(admin);

		// wrap up the deployment
		renounceOwnership();
		deployed = true;
		emit DeployPerformed();
	}

	event DeployPerformed();
}

library LibDeployer1
{
	function publishContract() public returns (address _address)
	{
	}
}
