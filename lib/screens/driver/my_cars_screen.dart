import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../models/car_profile.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import 'car_setup_screen.dart';
import '../../models/enums.dart';
import '../auth/register_screen.dart';

class MyCarsScreen extends StatefulWidget {
  const MyCarsScreen({super.key});
  @override
  State<MyCarsScreen> createState() => _MyCarsScreenState();
}

class _MyCarsScreenState extends State<MyCarsScreen> {
  Future<void> _openAdd() async {
    final ok = await ensureRegistered(context);
    if (!ok || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CarSetupScreen()));
    setState(() {});
  }

  Future<void> _openEdit(CarProfile car) async {
    final ok = await ensureRegistered(context);
    if (!ok || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CarSetupScreen(existing: car)));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cars = app.cars;
    return Scaffold(
      appBar: const PsEvAppBar(title: 'My Cars'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('My Cars (${cars.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          if (cars.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('You have not added a car yet.', style: TextStyle(color: PsEvColors.mutedText))),
            )
          else
            ...cars.map((car) {
              final isActive = car.carId == app.activeCarId || (app.activeCarId == null && car == cars.first);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF0D9488)]),
                              borderRadius: BorderRadius.circular(PsEvRadii.iconBox),
                            ),
                            child: const Icon(Icons.electric_car, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(car.carModel, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('Plate: ${car.plateNumber.isEmpty ? 'Not added' : car.plateNumber}', style: const TextStyle(color: PsEvColors.emerald, fontSize: 12, fontWeight: FontWeight.w700)),
                                Text(
                                  '${car.maxAmpere.toStringAsFixed(0)}A • ${car.connector.label} • ${car.chargingStandard.shortLabel}',
                                  style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (isActive) PsEvTag.price(label: 'Active'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _openEdit(car),
                              child: const Text('Edit'),
                            ),
                          ),
                          if (!isActive) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => app.setActiveCar(car.carId),
                                child: const Text('Set Active'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
          PsEvFilledButton(
            label: cars.isEmpty ? '+ Add Your First Car' : '+ Add Another Car',
            icon: Icons.add,
            onTap: _openAdd,
          ),
        ],
      ),
    );
  }
}
