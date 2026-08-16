import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../services/booking_service.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import '../auth/register_screen.dart';
import 'charger_form_screen.dart';
import 'manage_charger_screen.dart';
import 'host_scan_screen.dart';
import '../../models/enums.dart';

class HostHomeScreen extends StatefulWidget {
  const HostHomeScreen({super.key});
  @override
  State<HostHomeScreen> createState() => _HostHomeScreenState();
}

class _HostHomeScreenState extends State<HostHomeScreen> {
  Future<void> _onAddChargerTap(BuildContext context) async {
    final ok = await ensureRegistered(context);
    if (!ok || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ChargerFormScreen()));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final bookingService = context.watch<BookingService>();
    final chargers = app.myChargers;
    final activeSessions = bookingService.activeForHost(kCurrentUserId).length;
    return Scaffold(
      appBar: PsEvAppBar(
        title: 'Host Home',
        showBrandRow: true,
        actions: const [PsEvModePill(label: 'host mode')],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('My Chargers (${chargers.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          if (chargers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('You have not added a charger yet.', style: TextStyle(color: PsEvColors.mutedText))),
            )
          else
            ...chargers.map((ch) {
              final pendingCount = bookingService.pendingApprovalsForHost(kCurrentUserId).where((b) => b.chargerId == ch.chargerId).length;
              final bookedCount = bookingService.confirmedForHost(kCurrentUserId).where((b) => b.chargerId == ch.chargerId).length;
              final chargingCount = bookingService.inProgressForHost(kCurrentUserId).where((b) => b.chargerId == ch.chargerId).length;
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(PsEvRadii.card),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => ManageChargerScreen(charger: ch)));
                    setState(() {});
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF0D9488)]),
                            borderRadius: BorderRadius.circular(PsEvRadii.iconBox),
                          ),
                          child: ch.photoBytes != null ? Image.memory(ch.photoBytes!, fit: BoxFit.cover) : const Icon(Icons.ev_station, color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ch.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('${ch.city} • ${ch.area} • ${ch.powerKw} kW • ${ch.ampere}A • ${ch.connector.label} • ${ch.priceLabel}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                              if (ch.residentsOnly)
                                Padding(padding: const EdgeInsets.only(top: 4), child: PsEvTag.restricted(label: '${ch.restrictedCommunity} only')),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (pendingCount > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: PsEvStatusPill(label: '$pendingCount pending', background: PsEvColors.amberChip, textColor: PsEvColors.amberChipText),
                                    ),
                                  if (bookedCount > 0)
                                    Padding(padding: const EdgeInsets.only(top: 4), child: PsEvStatusPill.bookedAwaitingScan()),
                                  if (chargingCount > 0)
                                    Padding(padding: const EdgeInsets.only(top: 4), child: PsEvStatusPill.charging()),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => _onAddChargerTap(context),
            child: Text(chargers.isEmpty ? '+ Add Your First Charger' : '+ Add Another Charger'),
          ),
          const SizedBox(height: 16),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(PsEvRadii.card),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HostScanScreen())),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(color: PsEvColors.emeraldPale, shape: BoxShape.circle),
                      child: const Icon(Icons.qr_code_scanner, color: PsEvColors.emerald),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Active Sessions', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('$activeSessions awaiting start or in progress', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
