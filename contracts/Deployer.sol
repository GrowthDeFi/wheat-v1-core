// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

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
		// bytes memory _bytecode = abi.encodePacked(type(Contract).creationCode);
		// Contract(_address).construct();
		// return Create2.deploy(0, bytes32(0), _bytecode);
	}
}
