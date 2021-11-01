const chai = require('chai')
const { expect } = require('chai')
const BN = require('bn.js')
chai.use(require('chai-bn')(BN))
const { developmentChains } = require('../../helper-hardhat-config')

describe('RandomNumberConsumer Integration Tests', async function () {

  let randomNumberConsumer;
  let randomNumberConsumerAddress;

  beforeEach(async () => {
    const RandomNumberConsumer = await deployments.get('RandomNumberConsumer');
    randomNumberConsumerAddress = RandomNumberConsumer.address;
    randomNumberConsumer = await ethers.getContractAt('RandomNumberConsumer', randomNumberConsumerAddress);
  })

  it('Should successfully make a VRF request and get a result', async () => {

    console.log("Running random number request")

    const transaction = await randomNumberConsumer.getRandomNumber()
    const tx_receipt = await transaction.wait()
    const requestId = tx_receipt.events[2].topics[1]

    let startingValue = await randomNumberConsumer.randomResult(requestId)
    console.log("VRF Starting Value: ", new ethers.BigNumber.from(startingValue._hex).toString())

    const awaitFulfillment = async () => {
      const chainId = await getChainId();
      if(chainId === '31337') {
        // is localhost, use VRFCoordinatorMock to fulfil randomness request
        const VRFCoordinatorMock = await deployments.get('VRFCoordinatorMock')
        let vrfCoordinatorMock = await ethers.getContractAt('VRFCoordinatorMock', VRFCoordinatorMock.address);
        let callbackTransaction = await vrfCoordinatorMock.callBackWithRandomness(requestId, "20273464752896995353136718257338856642066504105906912382411228684473618923620", randomNumberConsumerAddress);
        await callbackTransaction.wait();
      } else {
        // wait 1 min for oracle to callback
        await new Promise(resolve => setTimeout(resolve, 60000))
      }
      result = await randomNumberConsumer.randomResult(requestId)
      if(new ethers.BigNumber.from(result._hex).toString() === new ethers.BigNumber.from(startingValue._hex).toString()) {
        console.log("Fulfillment incomplete: waiting another minute for randomness fulfillment");
        await awaitFulfillment()
      }
    }

    console.log("Waiting one minute for randomness fulfillment");
    await awaitFulfillment();

    let vrfResult = new ethers.BigNumber.from(result._hex).toString();

    console.log("VRF Result: ", vrfResult)
    expect(vrfResult).to.be.a.bignumber.that.is.greaterThan(new ethers.BigNumber.from(0).toString())

    // Example offset generation:
    let exampleSupply = new BN(10000);
    let randomNumber = new BN(vrfResult);
    let randomOffset = randomNumber.mod(exampleSupply);

    console.log("Example random offset for an NFT contract with a supply of 10000:", randomOffset.toString());
  })
})