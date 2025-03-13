const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { deployContractsAndSetVariables } = require("./helpers/setup-contracts");
const {
  setUpAccessManagerIntermediary,
} = require("./helpers/access-manager-setup");
const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("Sale Intermediary Tests", function () {
  async function setUpSaleIntermediaryTests() {
    const {
      owner,
      investor1,
      investor2,
      custodian,
      facilitator,
      state_changer,
      remoratoken,
      allowlist,
      ausd,
      accessmanager,
    } = await deployContractsAndSetVariables(10, 50, 10000, 0, true);
    //token supply: 10
    //transfer fee: 50 = 50 cents (not doing up to 6 decimals in this test)
    //rent fee: 10%

    const SaleIntermediary = await ethers.getContractFactory(
      "RemoraSaleIntermediary"
    );
    const saleIntermediary = await SaleIntermediary.deploy(
      accessmanager.target,
      owner.address,
      owner.address
    );
    await saleIntermediary.waitForDeployment();

    const RMRACoin = await ethers.getContractFactory("RMRA");
    const rmra = await RMRACoin.deploy("Remora Coin", "RMRA", 1000);

    await setUpAccessManagerIntermediary(
      accessmanager,
      remoratoken,
      custodian,
      saleIntermediary,
      facilitator
    );

    await ausd.transfer(investor1.address, 1000);

    return {
      owner,
      investor1,
      investor2,
      custodian,
      facilitator,
      state_changer,
      remoratoken,
      allowlist,
      ausd,
      rmra,
      accessmanager,
      saleIntermediary,
    };
  }

  describe("processRwaSale Tests", function () {
    it("Should revert due to insufficient allowed balance from buyer", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        ausd,
        allowlist,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryTests);

      //need to add user to allowlist to allow token trade
      await allowlist.connect(custodian).allowUser(investor1.address);

      //make only one approval
      await remoratoken.approve(saleIntermediary.target, 10);

      const tradeData = {
        seller: owner.address,
        buyer: investor1.address,
        assetSold: remoratoken.target,
        assetSoldAmount: 10,
        assetReceived: ausd.target,
        assetReceivedAmount: 1000,
        hasSellerFee: false,
        feeAmount: 0,
        feeToken: ausd.target,
      };

      await expect(
        saleIntermediary.connect(facilitator).processRwaSale(
          // 1000 tokens of ausd for 10 remoratokens
          tradeData
        )
      ).to.be.revertedWithCustomError(ausd, "ERC20InsufficientAllowance");
    });

    it("Should revert due to insufficient allowed balance from seller", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        ausd,
        allowlist,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryTests);

      //need to add user to allowlist to allow token trade
      await allowlist.connect(custodian).allowUser(investor1.address);

      //make only one approval
      await ausd.connect(investor1).approve(saleIntermediary.target, 1000);

      const tradeData = {
        seller: owner.address,
        buyer: investor1.address,
        assetSold: remoratoken.target,
        assetSoldAmount: 10,
        assetReceived: ausd.target,
        assetReceivedAmount: 1000,
        hasSellerFee: false,
        feeAmount: 0,
        feeToken: ausd.target,
      };

      await expect(
        saleIntermediary.connect(facilitator).processRwaSale(
          // 1000 tokens of ausd for 10 remoratokens
          tradeData
        )
      ).to.be.revertedWithCustomError(
        remoratoken,
        "ERC20InsufficientAllowance"
      );
    });

    it("Should revert due to call from unauthorized account", async function () {
      const {
        owner,
        investor1,
        custodian,
        remoratoken,
        ausd,
        allowlist,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryTests);

      await allowlist.connect(custodian).allowUser(investor1.address);

      //make proper approvals
      await remoratoken.approve(saleIntermediary.target, 10);
      await ausd.connect(investor1).approve(saleIntermediary.target, 1000);

      const tradeData = {
        seller: owner.address,
        buyer: investor1.address,
        assetSold: remoratoken.target,
        assetSoldAmount: 10,
        assetReceived: ausd.target,
        assetReceivedAmount: 1000,
        hasSellerFee: false,
        feeAmount: 0,
        feeToken: ausd.target,
      };

      await expect(
        saleIntermediary.processRwaSale(
          // 1000 tokens of ausd for 10 remoratokens
          tradeData
        )
      ).to.be.revertedWithCustomError(
        saleIntermediary,
        "AccessManagedUnauthorized"
      );
    });

    it("Should revert transfer due to no fee approval", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        ausd,
        allowlist,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryTests);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await saleIntermediary
        .connect(custodian)
        .setFeeRecipient(custodian.address);

      //make proper approvals, except fee approval
      await remoratoken.approve(saleIntermediary.target, 10);
      await ausd.connect(investor1).approve(saleIntermediary.target, 1000);

      const tradeData = {
        seller: owner.address,
        buyer: investor1.address,
        assetSold: remoratoken.target,
        assetSoldAmount: 10,
        assetReceived: ausd.target,
        assetReceivedAmount: 1000,
        hasSellerFee: true,
        feeAmount: 100,
        feeToken: ausd.target,
      };

      await expect(
        saleIntermediary.connect(facilitator).processRwaSale(
          // 1000 tokens of ausd for 10 remoratokens
          tradeData
        )
      ).to.be.revertedWithCustomError(ausd, "ERC20InsufficientAllowance");
    });

    it("Should successfully transfer remoratoken for ausd, with fee collected", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        ausd,
        allowlist,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryTests);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await saleIntermediary
        .connect(custodian)
        .setFeeRecipient(custodian.address);

      //make proper approvals
      await remoratoken.approve(saleIntermediary.target, 10);
      await ausd.approve(saleIntermediary.target, 100);
      await ausd.connect(investor1).approve(saleIntermediary.target, 1000);

      const tradeData = {
        seller: owner.address,
        buyer: investor1.address,
        assetSold: remoratoken.target,
        assetSoldAmount: 10,
        assetReceived: ausd.target,
        assetReceivedAmount: 1000,
        hasSellerFee: true,
        feeAmount: 100,
        feeToken: ausd.target,
      };

      const tx = saleIntermediary.connect(facilitator).processRwaSale(
        // 1000 tokens of ausd for 10 remoratokens
        tradeData
      );

      await expect(tx).to.changeTokenBalances(
        remoratoken,
        [investor1, owner],
        [+10, -10]
      );
      await expect(tx).to.changeTokenBalances(
        ausd,
        [investor1, owner, custodian],
        [-1000, +900, +100]
      );
    });

    it("Should successfully transfer remoratoken for ausd, with no fee collected", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        ausd,
        allowlist,
        saleIntermediary,
      } = await loadFixture(setUpSaleIntermediaryTests);

      await allowlist.connect(custodian).allowUser(investor1.address);

      //make proper approvals
      await remoratoken.approve(saleIntermediary.target, 10);
      await ausd.connect(investor1).approve(saleIntermediary.target, 1000);

      const tradeData = {
        seller: owner.address,
        buyer: investor1.address,
        assetSold: remoratoken.target,
        assetSoldAmount: 10,
        assetReceived: ausd.target,
        assetReceivedAmount: 1000,
        hasSellerFee: false,
        feeAmount: 0,
        feeToken: ausd.target,
      };

      const tx = saleIntermediary.connect(facilitator).processRwaSale(
        // 1000 tokens of ausd for 10 remoratokens
        tradeData
      );

      await expect(tx).to.changeTokenBalances(
        remoratoken,
        [investor1, owner],
        [+10, -10]
      );
      await expect(tx).to.changeTokenBalances(
        ausd,
        [investor1, owner],
        [-1000, +1000]
      );
    });
  });
});
