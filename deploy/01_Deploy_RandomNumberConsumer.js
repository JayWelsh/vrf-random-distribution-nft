let {networkConfig} = require('../helper-hardhat-config')

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

module.exports = async ({
  getNamedAccounts,
  deployments,
  getChainId
}) => {

  const { deploy, get, log } = deployments
  const { deployer } = await getNamedAccounts()
  const chainId = await getChainId()
  let linkTokenAddress
  let vrfCoordinatorAddress
  let additionalMessage = ""

  if (chainId == 31337) {
    linkToken = await get('LinkToken')
    VRFCoordinatorMock = await get('VRFCoordinatorMock')
    linkTokenAddress = linkToken.address
    vrfCoordinatorAddress = VRFCoordinatorMock.address
    additionalMessage = " --linkaddress " + linkTokenAddress
  } else {
    linkTokenAddress = networkConfig[chainId]['linkToken']
    vrfCoordinatorAddress = networkConfig[chainId]['vrfCoordinator']
  }
  const keyHash = networkConfig[chainId]['keyHash']
  const fee = networkConfig[chainId]['fee']

  let args = [vrfCoordinatorAddress, linkTokenAddress, keyHash, fee];

  const randomNumberConsumer = await deploy('RandomNumberConsumer', {
    from: deployer,
    args,
    log: true
  })

  if([1, 4, 5, 42].indexOf(Number(chainId)) > -1) {
    // Run etherscan verification on mainnet, rinkeby, goerli & kovan
    await sleep(45000);
    await hre.run("verify:verify", {
        address: randomNumberConsumer.address,
        constructorArguments: args,
    })
  }

  log("Run the following command to fund contract with LINK:")
  log("npx hardhat fund-link --contract " + randomNumberConsumer.address + " --network " + networkConfig[chainId]['name'] + additionalMessage)
  log("Then run RandomNumberConsumer contract with the following command")
  log("npx hardhat request-random-number --contract " + randomNumberConsumer.address + " --network " + networkConfig[chainId]['name'])
  log("----------------------------------------------------")
}

module.exports.tags = ['ReservationVariant', 'OffsetVariant']
