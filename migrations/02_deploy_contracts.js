const Deployer = artifacts.require('Deployer');
const LibDeployer1 = artifacts.require('LibDeployer1');

module.exports = async (deployer, network, [account]) => {
  console.log('Preparing the deployer contract...');
  await deployer.deploy(LibDeployer1);
  deployer.link(LibDeployer1, Deployer);
  await deployer.deploy(Deployer);

  if (['development'].includes(network)) {
    console.log('Performing the deploy...');
    const contract = await Deployer.deployed();
    await contract.deploy();
  }
};
