import '../models/enums.dart';

class PriceLimits {
  final double min;
  final double max;
  final String unitLabel;
  const PriceLimits({required this.min, required this.max, required this.unitLabel});
}

class PricingService {
  static const Map<PricingModel, PriceLimits> limits = {
    PricingModel.perMinute: PriceLimits(min: 0.5, max: 5, unitLabel: 'EGP/min'),
    PricingModel.perKwh: PriceLimits(min: 1, max: 8, unitLabel: 'EGP/kWh'),
  };

  static PriceLimits limitsFor(PricingModel model) => limits[model]!;

  static bool isPriceValid(PricingModel model, double price) {
    final l = limitsFor(model);
    return price >= l.min && price <= l.max;
  }

  static double minutesPerKwh(double powerKw) => powerKw > 0 ? 60 / powerKw : 0;

  static double computeCostRaw({
    required PricingModel model,
    required double price,
    required double powerKw,
    required double minutes,
  }) {
    if (model == PricingModel.perKwh) {
      final kwhDelivered = powerKw * (minutes / 60);
      return price * kwhDelivered;
    }
    return price * minutes;
  }

  /// Rounded-to-whole-EGP cost. ALWAYS use this (not computeCostRaw) when
  /// the result will be displayed, held from/compared against a wallet
  /// balance, or stored on a Booking.
  static double computeCost({
    required PricingModel model,
    required double price,
    required double powerKw,
    required double minutes,
  }) {
    final raw = computeCostRaw(model: model, price: price, powerKw: powerKw, minutes: minutes);
    return raw.roundToDouble();
  }

  static String priceLabel(PricingModel model, double price) {
    final unit = limitsFor(model).unitLabel;
    return '${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)} $unit';
  }

  static String hintText(PricingModel model, double powerKw, double price) {
    if (powerKw <= 0 || price <= 0) return _rangeText(model);
    final minPerKwh = minutesPerKwh(powerKw);
    final buffer = StringBuffer();
    if (model == PricingModel.perKwh) {
      final perMinuteEquivalent = minPerKwh > 0 ? price / minPerKwh : 0;
      buffer.write('At ${powerKw.toStringAsFixed(1)} kW, this is ≈ '
          '${perMinuteEquivalent.toStringAsFixed(2)} EGP/min equivalent '
          '(≈ ${minPerKwh.toStringAsFixed(1)} min per kWh). ');
    } else {
      final perKwhEquivalent = price * minPerKwh;
      buffer.write('At ${powerKw.toStringAsFixed(1)} kW, this is ≈ '
          '${perKwhEquivalent.toStringAsFixed(2)} EGP/kWh equivalent '
          '(≈ ${minPerKwh.toStringAsFixed(1)} min per kWh). ');
    }
    buffer.write(_rangeText(model));
    return buffer.toString();
  }

  static String _rangeText(PricingModel model) {
    final l = limitsFor(model);
    return 'Allowed range: ${l.min}–${l.max} ${l.unitLabel}.';
  }
}
