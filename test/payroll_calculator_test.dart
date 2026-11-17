// test/payroll_calculator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:your_app/services/payroll_calculator.dart'; // palitan ang package name

void main() {
  const s = PayrollSettings();

  test('Contributions @17k', () {
    expect(PayrollCalculator.calcSss(17000, s), closeTo(850, 0.01));
    expect(PayrollCalculator.calcPhilhealth(17000, s), closeTo(425, 0.01));
    expect(PayrollCalculator.calcPagibig(17000, s), closeTo(200, 0.01));
  });

  test('SSS MSC cap and Pag-IBIG cap', () {
    expect(PayrollCalculator.calcSss(60000, s), closeTo(1750, 0.01));
    expect(PayrollCalculator.calcPagibig(60000, s), closeTo(200, 0.01));
  });

  test('Tax brackets', () {
    expect(PayrollCalculator.calcWithholdingTax(27550, s), closeTo(1007.55, 0.01));
    expect(PayrollCalculator.calcWithholdingTax(46925, s), closeTo(4593.40, 0.01));
  });

  test('Full month 30k, statutory contributions', () {
    final b = PayrollCalculator.computeFromData(
      employee: {'basicSalary': 30000, 'workingDaysPerMonth': 22},
      expectedDays: 22,
      present: 1,
      workHours: const WorkHoursTotals(),
      settings: const PayrollSettings(prorateContributions: false),
    );
    expect(b.sss, closeTo(1500, 0.01));
  });

  test('OT / rest day / ND multipliers', () {
    final b = PayrollCalculator.computeFromData(
      employee: {'dailyRate': 1000, 'workingDaysPerMonth': 22},
      expectedDays: 22,
      present: 22,
      workHours: const WorkHoursTotals(
        regularOtMinutes: 120,
        restDayRegularMinutes: 480,
        restDayOtMinutes: 120,
        nightDiffMinutes: 240,
      ),
      settings: s,
    );
    expect(b.overtimeAmount, closeTo(312.50, 0.01));
    expect(b.dayOffOtAmount, closeTo(1722.50, 0.01)); // 1300 + 422.50
    expect(b.nightDiffAmount, closeTo(50.00, 0.01));
  });
}