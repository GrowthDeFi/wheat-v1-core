const Deployer = artifacts.require('Deployer');
const LibDeployer1 = artifacts.require('LibDeployer1');
const LibDeployer2 = artifacts.require('LibDeployer2');
const LibDeployer3 = artifacts.require('LibDeployer3');
const UniswapV2LiquidityPoolAbstraction = artifacts.require('UniswapV2LiquidityPoolAbstraction');

module.exports = async (deployer, network, [account]) => {
  console.log('Preparing the deployer contract...');
  await deployer.deploy(UniswapV2LiquidityPoolAbstraction);
  await deployer.deploy(LibDeployer1);
  await deployer.deploy(LibDeployer2);
  deployer.link(UniswapV2LiquidityPoolAbstraction, LibDeployer3);
  await deployer.deploy(LibDeployer3);
  deployer.link(LibDeployer1, Deployer);
  deployer.link(LibDeployer2, Deployer);
  deployer.link(LibDeployer3, Deployer);
  await deployer.deploy(Deployer);

  if (['development'].includes(network)) {
    console.log('Performing the deploy...');
    const contract = await Deployer.deployed();
    await contract.deploy();
  }
};
