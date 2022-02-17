const Pool = artifacts.require("Pool");
const PToken = artifacts.require("PToken");

module.exports = function (deployer, network, accounts) {
    switch (network) {
        case "development_pool":
            // Fill required parameters before deploy.
            deployer.deploy(Pool);
            break;

        case "development_ptoken":
            // Fill required parameters before deploy.
            deployer.deploy(PToken);
            break;
    }
}
