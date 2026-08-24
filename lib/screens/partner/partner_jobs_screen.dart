import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/partner_service.dart';
import '../../state/app_state.dart';
import '../../models/partner_models.dart';
import '../../theme/ps_ev_theme.dart';

/// Partner-facing screen: shows the shared pool of OPEN service requests
/// (first partner to tap "Accept" gets it - no manual admin dispatch
/// step, since there can be multiple partners) and this partner's own
/// accepted jobs, which can be marked complete.
///
/// The Open Requests tab has category filter chips (All / Station /
/// Adaptor / Cable / Maintenance / Other) so a partner who only handles
/// cables, for example, doesn't need to scroll past every station-
/// install request.
///
/// Only reachable if PartnerService.isPartner is true for the signed-in
/// user (see ProfileScreen, which conditionally shows the entry point).
///
/// NOTE: uses a plain Flutter AppBar (not PsEvAppBar) because this
/// screen needs a `bottom: TabBar(...)`, which PsEvAppBar's constructor
/// does not expose.
class PartnerJobsScreen extends StatefulWidget {
  const PartnerJobsScreen({super.key});

  @override
  State<PartnerJobsScreen> createState() => _PartnerJobsScreenState();
}

class _PartnerJobsScreenState extends State<PartnerJobsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  ServiceCategory? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  IconData _categoryIcon(ServiceCategory c) {
    switch (c) {
      case ServiceCategory.station:
        return Icons.ev_station;
      case ServiceCategory.adaptor:
        return Icons.settings_input_hdmi;
      case ServiceCategory.cable:
        return Icons.cable;
      case ServiceCategory.maintenance:
        return Icons.build_circle_outlined;
      case ServiceCategory.other:
        return Icons.help_outline;
    }
  }

  Future<void> _accept(BuildContext context, InstallationRequest request) async {
    final app = context.read<AppState>();
    final auth = context.read<AuthService>();
    final partnerService = context.read<PartnerService>();

    final ok = await partnerService.acceptInstallationRequest(
      request.id,
      partnerId: app.currentUserId ?? '',
      partnerName: auth.displayName,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Job accepted - contact the driver to schedule.' : 'This job was just taken by another partner.')),
    );
  }

  Future<void> _markComplete(BuildContext context, InstallationRequest request) async {
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark Job Complete'),
        content: TextField(
          controller: notesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Completion notes (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark Complete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<PartnerService>().completeInstallationRequest(
          request.id,
          completionNotes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final partnerService = context.watch<PartnerService>();
    final open = partnerService.openRequestsForCategory(_categoryFilter);
    final myJobs = partnerService.myPartnerJobs;
    final dateFmt = DateFormat('MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Partner Jobs'),
        backgroundColor: Colors.white,
        foregroundColor: PsEvColors.slate950,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: PsEvColors.emerald,
          unselectedLabelColor: PsEvColors.mutedText,
          indicatorColor: PsEvColors.emerald,
          tabs: [
            Tab(text: 'Open Requests (${open.length})'),
            Tab(text: 'My Jobs (${myJobs.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // -------------------- Open pool --------------------
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: _categoryFilter == null,
                          onSelected: (_) => setState(() => _categoryFilter = null),
                          label: const Text('All'),
                          selectedColor: PsEvColors.emerald,
                          labelStyle: TextStyle(
                            color: _categoryFilter == null ? Colors.white : PsEvColors.slateText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          backgroundColor: PsEvColors.slate100,
                        ),
                      ),
                      ...ServiceCategory.values.map((c) {
                        final selected = _categoryFilter == c;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: selected,
                            onSelected: (_) => setState(() => _categoryFilter = c),
                            avatar: Icon(_categoryIcon(c), size: 14, color: selected ? Colors.white : PsEvColors.mutedText),
                            label: Text(c.shortLabel),
                            selectedColor: PsEvColors.emerald,
                            labelStyle: TextStyle(color: selected ? Colors.white : PsEvColors.slateText, fontSize: 12, fontWeight: FontWeight.w600),
                            backgroundColor: PsEvColors.slate100,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: open.isEmpty
                    ? const Center(child: Text('No open requests in this category right now.', style: TextStyle(color: PsEvColors.mutedText)))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: open
                            .map((r) => Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(_categoryIcon(r.category), size: 15, color: PsEvColors.emerald),
                                            const SizedBox(width: 6),
                                            Text(r.category.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.emerald)),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text('${r.area}, ${r.city}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        const SizedBox(height: 4),
                                        Text(r.addressDetails, style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                                        if (r.notes != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text('Note: ${r.notes}', style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                                          ),
                                        const SizedBox(height: 4),
                                        Text('Requested ${dateFmt.format(r.createdAt)}', style: const TextStyle(fontSize: 11, color: PsEvColors.mutedText)),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(r.driverName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                                Text(r.driverPhone, style: const TextStyle(fontSize: 11, color: PsEvColors.mutedText)),
                                              ],
                                            ),
                                            ElevatedButton(
                                              onPressed: () => _accept(context, r),
                                              child: const Text('Accept'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
              ),
            ],
          ),
          // -------------------- My jobs --------------------
          myJobs.isEmpty
              ? const Center(child: Text('No jobs yet - accept an open request to get started.', style: TextStyle(color: PsEvColors.mutedText)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: myJobs
                      .map((r) => Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(_categoryIcon(r.category), size: 14, color: PsEvColors.emerald),
                                          const SizedBox(width: 6),
                                          Text('${r.area}, ${r.city}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        ],
                                      ),
                                      PsEvStatusPill(
                                        label: r.status.name,
                                        background: r.status == InstallRequestStatus.completed
                                            ? PsEvColors.emeraldPale
                                            : PsEvColors.slate200,
                                        textColor: r.status == InstallRequestStatus.completed
                                            ? PsEvColors.emeraldChipText
                                            : PsEvColors.slateText,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(r.category.label, style: const TextStyle(fontSize: 11, color: PsEvColors.emerald, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(r.addressDetails, style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                                  const SizedBox(height: 4),
                                  Text('${r.driverName} · ${r.driverPhone}', style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                                  if (r.status == InstallRequestStatus.accepted)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: ElevatedButton(
                                          onPressed: () => _markComplete(context, r),
                                          child: const Text('Mark Complete'),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ))
                      .toList(),
                ),
        ],
      ),
    );
  }
}
