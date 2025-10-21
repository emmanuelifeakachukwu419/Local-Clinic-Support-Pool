import { Cl } from "@stacks/transactions";
import { describe, expect, it } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

describe("Appointment Scheduler Smart Contract", () => {
  it("ensures simnet is initialized", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("should initialize with sample clinic", () => {
    const { result } = simnet.callReadOnlyFn(
      "appointment-scheduler",
      "get-clinic-availability",
      [Cl.uint(1)],
      deployer
    );
    
    expect(result).toBeSome(
      Cl.tuple({
        name: Cl.stringAscii("General Health Clinic"),
        "operating-hours": Cl.list([
          Cl.uint(900), Cl.uint(1000), Cl.uint(1100),
          Cl.uint(1400), Cl.uint(1500), Cl.uint(1600)
        ]),
        "max-daily-appointments": Cl.uint(20),
        "advance-booking-days": Cl.uint(30),
        "is-active": Cl.bool(true)
      })
    );
  });

  it("should show correct initial system stats", () => {
    const { result } = simnet.callReadOnlyFn(
      "appointment-scheduler",
      "get-system-stats",
      [],
      deployer
    );
    
    expect(result).toBeOk(
      Cl.tuple({
        "total-appointments": Cl.uint(0),
        "next-appointment-id": Cl.uint(1)
      })
    );
  });

  it("should validate time slots correctly", () => {
    // Valid time slot
    const valid = simnet.callReadOnlyFn(
      "appointment-scheduler",
      "is-valid-time-slot",
      [Cl.uint(900)],
      deployer
    );
    expect(valid.result).toBeBool(true);

    // Invalid time slot
    const invalid = simnet.callReadOnlyFn(
      "appointment-scheduler",
      "is-valid-time-slot",
      [Cl.uint(1200)],
      deployer
    );
    expect(invalid.result).toBeBool(false);
  });

  it("should successfully book an appointment", () => {
    const futureDate = simnet.blockHeight + 100;
    
    const { result } = simnet.callPublicFn(
      "appointment-scheduler",
      "book-appointment",
      [
        Cl.uint(1), // clinic-id
        Cl.uint(futureDate), // appointment-date
        Cl.uint(900), // time-slot (9:00 AM)
        Cl.stringAscii("check-up"), // appointment-type
        Cl.stringAscii("Dr. Smith"), // doctor
        Cl.stringAscii("Regular checkup") // notes
      ],
      wallet1
    );

    expect(result).toBeOk(Cl.uint(1)); // First appointment ID
  });

  it("should reject booking with invalid time slot", () => {
    const futureDate = simnet.blockHeight + 200;
    
    const { result } = simnet.callPublicFn(
      "appointment-scheduler",
      "book-appointment",
      [
        Cl.uint(1),
        Cl.uint(futureDate),
        Cl.uint(1300), // Invalid time slot
        Cl.stringAscii("check-up"),
        Cl.stringAscii("Dr. Smith"),
        Cl.stringAscii("Regular checkup")
      ],
      wallet1
    );

    expect(result).toBeErr(Cl.uint(302)); // ERR-INVALID-TIME-SLOT
  });

  it("should reject booking in the past", () => {
    const pastDate = 1; // Very low block height (past)
    
    const { result } = simnet.callPublicFn(
      "appointment-scheduler",
      "book-appointment",
      [
        Cl.uint(1),
        Cl.uint(pastDate), // Past date
        Cl.uint(900),
        Cl.stringAscii("check-up"),
        Cl.stringAscii("Dr. Smith"),
        Cl.stringAscii("Regular checkup")
      ],
      wallet1
    );

    expect(result).toBeErr(Cl.uint(305)); // ERR-PAST-DATE
  });
});
