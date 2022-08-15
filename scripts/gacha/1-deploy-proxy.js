require('dotenv').config();

const hre = require("hardhat");
const CONTRACT_NAME = "GachaContract";
const OWNER_ADDRESS = process.env.ADDRESS;

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    console.log("Deployer:", deployer.address);
    console.log("Balance:", (await deployer.getBalance()).toString());

    const factory = await hre.ethers.getContractFactory(CONTRACT_NAME);
    console.log(`Deploying ${CONTRACT_NAME}...`);

    const param = {
        boxContract: "0x7eB87F93C513a59BE74fb804954019B9be48b98b", //BOX_CONTRACT_PROXY_ADDRESS
        ownerAddress: OWNER_ADDRESS
    }

    const contract = await hre.upgrades.deployProxy(
        factory,
        [
            param.boxContract,
            param.ownerAddress
        ],
        {
            kind: "uups"
        }
    );
    await contract.deployed();

    let logicAddress = await hre.upgrades.erc1967.getImplementationAddress(contract.address);
    console.log(`${CONTRACT_NAME} proxy address: ${contract.address}`);
    console.log(`${CONTRACT_NAME} logic address: ${logicAddress}`);
}

main()
    .then(() => {
        process.exit(0);
    })
    .catch(err => {
        console.error(err);
        process.exit(1);
    });
