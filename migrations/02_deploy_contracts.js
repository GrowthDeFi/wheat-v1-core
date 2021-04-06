const Deployer = artifacts.require('Deployer');
const LibDeployer1 = artifacts.require('LibDeployer1');
const LibDeployer2 = artifacts.require('LibDeployer2');
const LibDeployer3 = artifacts.require('LibDeployer3');
const LibDeployer4 = artifacts.require('LibDeployer4');
const LibRewardCompoundingStrategy = artifacts.require('LibRewardCompoundingStrategy');

module.exports = async (deployer, network, [account]) => {
  console.log('Preparing the deployer contract...');
  await deployer.deploy(LibRewardCompoundingStrategy);
  await deployer.deploy(LibDeployer1);
  await deployer.deploy(LibDeployer2);
  await deployer.deploy(LibDeployer3);
  deployer.link(LibRewardCompoundingStrategy, LibDeployer4);
  await deployer.deploy(LibDeployer4);
  deployer.link(LibDeployer1, Deployer);
  deployer.link(LibDeployer2, Deployer);
  deployer.link(LibDeployer3, Deployer);
  deployer.link(LibDeployer4, Deployer);
  await deployer.deploy(Deployer);

  if (['development'].includes(network)) {
    console.log('Performing the deploy...');
    const contract = await Deployer.deployed();
    const value = await contract.WBNB_LIQUIDITY_ALLOCATION();
    await contract.deploy({ value });

    console.log('Publishing batch 1...');
    await contract.batch1();

    console.log('Publishing batch 2...');
    await contract.batch2();

    console.log('Publishing batch 3...');
    await contract.batch3();

    console.log('Publishing batch 4...');
    await contract.batch4();

    console.log('Publishing batch 5...');
    await contract.batch5();

    console.log('Publishing batch 6...');
    await contract.batch6();
  }
};
