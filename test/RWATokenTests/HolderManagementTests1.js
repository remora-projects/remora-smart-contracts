const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { deployContractsAndSetVariables } = require("../helpers/SetUpContracts");
const { allowUsers } = require("../helpers/AccessManagerSetUp");
const { checkRents, payAndCalculate } = require("../helpers/HolderManagement");
const { expect } = require("chai");

describe("RemoraRWAToken Holder Management Tests 1", function () {
  describe("Holder Management Tests, distributions", function () {
    it("Should revert transfer due to frozen user, then allow after unfrozen", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
      } = await loadFixture(deployContractsAndSetVariables);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await remoratoken.approve(facilitator.address, 10);
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 10);

      await remoratoken.connect(investor1).approve(facilitator.address, 10);
      await remoratoken.connect(custodian).freezeHolder(investor1.address);

      await expect(
        remoratoken
          .connect(facilitator)
          .transferFrom(investor1.address, owner.address, 10)
      ).to.be.revertedWithCustomError(remoratoken, "UserIsFrozen");

      await remoratoken.connect(custodian).unFreezeHolder(investor1.address);

      await expect(
        remoratoken
          .connect(facilitator)
          .transferFrom(investor1.address, owner.address, 10)
      ).to.changeTokenBalances(remoratoken, [investor1, owner], [-10, +10]);
    });

    it("Should return 0 for user rent before distributing", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
      } = await loadFixture(deployContractsAndSetVariables);
      await allowlist.connect(custodian).allowUser(investor1.address);
      await remoratoken.approve(facilitator.address, 1);
      // transfer 1 token to investor
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 1); // user is now added as a new user.
      expect(
        (await remoratoken.rentBalance.staticCallResult(investor1.address)).at(
          0
        )
      ).to.equal(0);
    });

    it("Should revert claim of 0 when user buys and sells before any payout, at init", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
      } = await loadFixture(deployContractsAndSetVariables);

      const investors = [owner, investor1];
      const amounts = [BigInt(0), BigInt(0)];
      const totalSupply = await remoratoken.totalSupply();

      await allowUsers(custodian, allowlist, investors);
      await remoratoken.approve(facilitator.address, 10);

      //investor 1 has 2 tokens
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 2);

      expect(
        //should have no rent payout
        (await remoratoken.rentBalance.staticCallResult(investor1.address)).at(
          0
        )
      ).to.equal(0);
      await remoratoken.rentBalance(investor1.address); //non-static call

      //investor 1 has no more tokens
      await remoratoken.connect(investor1).approve(facilitator.address, 2);
      await remoratoken
        .connect(facilitator)
        .transferFrom(investor1.address, owner.address, 2);

      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        1000000000,
        totalSupply
      );
    });

    it("Should revert claim of 0 when user buys and sells before any payout", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
      } = await loadFixture(deployContractsAndSetVariables);

      const investors = [owner, investor1];
      const amounts = [BigInt(0), BigInt(0)];
      const totalSupply = await remoratoken.totalSupply();

      await allowUsers(custodian, allowlist, investors);
      await remoratoken.approve(facilitator.address, 10);

      //first payout
      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      //investor 1 has 2 tokens, enters at index 1
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 2);

      expect(
        //should have no rent payout
        (await remoratoken.rentBalance.staticCallResult(investor1.address)).at(
          0
        )
      ).to.equal(0);
      await remoratoken.rentBalance(investor1.address); //non-static call

      //investor 1 has no more tokens
      await remoratoken.connect(investor1).approve(facilitator.address, 2);
      await remoratoken
        .connect(facilitator)
        .transferFrom(investor1.address, owner.address, 2);

      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        1000000000,
        totalSupply
      );
    });

    it("Should allow user to claim rent after selling all tokens, but not payouts after", async function () {
      const {
        owner,
        investor1,
        facilitator,
        custodian,
        remoratoken,
        allowlist,
        ausd,
      } = await loadFixture(deployContractsAndSetVariables);

      const investors = [owner, investor1];
      const amounts = [BigInt(0), BigInt(0)];
      const totalSupply = await remoratoken.totalSupply();
      await remoratoken.connect(custodian).setFeePercentage(0); //no fee

      await allowUsers(custodian, allowlist, investors);
      await remoratoken.approve(facilitator.address, 10);

      //send $10,000 to the contract
      await ausd.transfer(remoratoken.target, 10000000000);

      //investor 1 has 2 tokens enters at init, 0
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 2);

      //first payout
      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      //investor 1 has 4 tokens
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 2);

      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      //investor 1 has no more tokens
      await remoratoken.connect(investor1).approve(facilitator.address, 4);
      await remoratoken
        .connect(facilitator)
        .transferFrom(investor1.address, owner.address, 4);

      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        1000000000,
        totalSupply
      );
      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      expect(
        await remoratoken.connect(investor1).claimRent()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-Number(amounts[1]), +Number(amounts[1])]
      );

      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        1000000000,
        totalSupply
      );

      await expect(
        remoratoken.connect(investor1).claimRent()
      ).to.be.revertedWithCustomError(remoratoken, "NoRentToClaim");
    });

    it("Should calculate correct rent even if buyer never checks rent after multiple distributions", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
        ausd,
      } = await loadFixture(deployContractsAndSetVariables);

      await remoratoken.connect(custodian).setFeePercentage(0); //no fee

      await allowlist.connect(custodian).allowUser(investor1.address);
      await remoratoken.approve(facilitator.address, 10);

      //send $10,000 to the contract
      await ausd.transfer(remoratoken.target, 10000000000);

      //investor 1 has 2 tokens enters at init, 0
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 4);

      //first payout
      await remoratoken.distributeRentalPayments(1000000000);
      await remoratoken.distributeRentalPayments(1000000000);
      await remoratoken.distributeRentalPayments(1000000000);
      await remoratoken.distributeRentalPayments(1000000000);
      await remoratoken.distributeRentalPayments(1000000000);

      expect(
        await remoratoken.connect(investor1).claimRent()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-2000000000, +2000000000]
      );
    });

    it("Should allow claim of older payouts but not new payouts, after User sold all tokens", async function () {
      const {
        owner,
        investor1,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
        ausd,
      } = await loadFixture(deployContractsAndSetVariables);

      await remoratoken.connect(custodian).setFeePercentage(0);

      await allowlist.connect(custodian).allowUser(investor1.address);
      await remoratoken.approve(facilitator.address, 10);

      //send $10,000 to the contract
      await ausd.transfer(remoratoken.target, 10000000000);

      //investor 1 has 2 tokens enters at init, 0
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 2);

      //first payout
      await remoratoken.distributeRentalPayments(1000000000);
      await remoratoken.distributeRentalPayments(1000000000);

      //investor has no more tokens
      await remoratoken.connect(investor1).approve(facilitator.address, 2);
      await remoratoken
        .connect(facilitator)
        .transferFrom(investor1.address, owner.address, 2);

      await remoratoken.distributeRentalPayments(1000000000);
      await remoratoken.distributeRentalPayments(1000000000);
      await remoratoken.distributeRentalPayments(1000000000);

      expect(
        await remoratoken.connect(investor1).claimRent()
      ).to.changeTokenBalances(
        ausd,
        [remoratoken, investor1],
        [-400000000, +400000000]
      );
    });

    it("Should distribute correct amount with multiple distributions, transfers in between, and investors at different points", async function () {
      const {
        owner,
        investor1,
        investor2,
        investor3,
        investor4,
        custodian,
        facilitator,
        allowlist,
        remoratoken,
      } = await loadFixture(deployContractsAndSetVariables);

      const totalSupply = BigInt(await remoratoken.totalSupply());
      const investors = [owner, investor1, investor2, investor3, investor4];
      const amounts = [BigInt(0), BigInt(0), BigInt(0), BigInt(0), BigInt(0)];

      await allowUsers(custodian, allowlist, investors);
      await remoratoken.approve(facilitator.address, 10);

      // transfer 1 token to investor
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 1); // user is now added as a new user.
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor2.address, 1);

      // Call distributeRentalPayments ($1000)
      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor2.address, 1);
      await checkRents(remoratoken, investors, amounts);

      // Call distributeRentalPayments ($1000)
      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor3.address, 1);
      await checkRents(remoratoken, investors, amounts);

      // Call distributeRentalPayments ($1000)
      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor2.address, 4);

      await checkRents(remoratoken, investors, amounts);

      await remoratoken.connect(investor2).approve(facilitator.address, 1);
      await remoratoken
        .connect(facilitator)
        .transferFrom(investor2, investor3, 1);

      // Call distributeRentalPayments ($1000)
      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor4.address, 1);

      await checkRents(remoratoken, investors, amounts);
    });

    it("Should distribute correct amount with multiple distributions, transfers in between, and investors at different points (with claims)", async function () {
      const {
        owner,
        investor1,
        investor2,
        investor3,
        investor4,
        custodian,
        facilitator,
        remoratoken,
        allowlist,
        ausd,
      } = await loadFixture(deployContractsAndSetVariables);

      const totalSupply = BigInt(await remoratoken.totalSupply());
      const investors = [owner, investor1, investor2, investor3, investor4];
      const amounts = [BigInt(0), BigInt(0), BigInt(0), BigInt(0), BigInt(0)];

      await allowUsers(custodian, allowlist, investors);
      await remoratoken.approve(facilitator.address, 10);

      //send $10,000 to the contract
      await ausd.transfer(remoratoken.target, 10000000000);

      // transfer 1 token to investor
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor1.address, 1); // user is now added as a new user.
      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor2.address, 1);

      // Call distributeRentalPayments ($1000)
      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor2.address, 1);

      await checkRents(remoratoken, investors, amounts);

      // Call distributeRentalPayments ($1000)
      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor3.address, 1);

      await checkRents(remoratoken, investors, amounts);

      await remoratoken.connect(investor1).claimRent(); // 0 for investor 1
      amounts[1] = BigInt(0);

      // Call distributeRentalPayments ($1000)
      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor2.address, 4); // 6 total

      await checkRents(remoratoken, investors, amounts);

      await remoratoken.connect(investor2).approve(facilitator.address, 1);
      await remoratoken
        .connect(facilitator)
        .transferFrom(investor2, investor3, 1);

      await remoratoken.connect(investor2).claimRent(); // 0 for investor 2
      amounts[2] = BigInt(0);

      // Call distributeRentalPayments ($1000)
      await payAndCalculate(
        remoratoken,
        investors,
        amounts,
        BigInt(1000000000),
        totalSupply
      );

      await remoratoken
        .connect(facilitator)
        .transferFrom(owner.address, investor4.address, 1);
      await checkRents(remoratoken, investors, amounts);
    });
  });
});
