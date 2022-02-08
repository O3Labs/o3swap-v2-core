const MathUtils = artifacts.require("MathUtils");
const Pool = artifacts.require("Pool");
const PToken = artifacts.require("PToken");

module.exports = function (deployer, network, accounts) {
    switch (network) {
        case "development_pool":
            deployer.deploy(MathUtils);
            deployer.link(MathUtils, Pool);

            // Fill required parameters before deploy.
            deployer.deploy(Pool);

        case "development_ptoken":
            // Fill required parameters before deploy.
            deployer.deploy(PToken);
    }
}
