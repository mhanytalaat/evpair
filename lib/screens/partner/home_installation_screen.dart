import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/partner_service.dart';
import '../../state/app_state.dart';
import '../../models/partner_models.dart';
import '../../theme/ps_ev_theme.dart';
import '../shared/location_picker_field.dart';

/// Driver-facing screen with two tabs:
///   - "Equipment" (now FIRST): browse the borrow/buy catalog (cables,
///     adaptors, home stations), filterable by type, each shown with a
///     photo when set - see _EquipmentTab.
///   - "Requests" (second): submit a categorized service request
///     (station, adaptor, cable, maintenance, other) and track status
///     of past requests - see _ServiceRequestTab. City/Area now use the
///     shared curated Egypt location list (LocationPickerField).
///
/// Reachable from Profile -> "Home Installation & Equipment".
///
/// NOTE: uses a plain Flutter AppBar (not PsEvAppBar) because this
/// screen needs a `bottom: TabBar(...)`, which PsEvAppBar's constructor
/// does not expose.
class HomeInstallationScreen extends StatefulWidget {
  const HomeInstallationScreen({super.key});

  @override
  State<HomeInstallationScreen> createState() => _HomeInstallationScreenState();
}

class _HomeInstallationScreenState extends State<HomeInstallationScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); // index 0 = Equipment, index 1 = Requests
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final partnerService = context.read<PartnerService>();
    if (app.currentUserId != null) {
      await partnerService.hydrate(app.currentUserId!);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Installation & Equipment'),
        backgroundColor: Colors.white,
        foregroundColor: PsEvColors.slate950,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: PsEvColors.emerald,
          unselectedLabelColor: PsEvColors.mutedText,
          indicatorColor: PsEvColors.emerald,
          tabs: const [
            Tab(text: 'Equipment'),
            Tab(text: 'Requests'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: const [
                _EquipmentTab(),
                _ServiceRequestTab(),
              ],
            ),
    );
  }
}

// ===========================================================================
// Tab 1: Equipment marketplace (now first) - categorized (Station /
// Adaptor / Cable / Other) with an owner-type badge (Partner / Brand /
// EVPair) and a product photo on each listing.
// ===========================================================================

class _EquipmentTab extends StatefulWidget {
  const _EquipmentTab();

  @override
  State<_EquipmentTab> createState() => _EquipmentTabState();
}

class _EquipmentTabState extends State<_EquipmentTab> {
  EquipmentType? _typeFilter;

  IconData _iconFor(EquipmentType type) {
    switch (type) {
      case EquipmentType.chargingCable:
        return Icons.cable;
      case EquipmentType.adaptor:
        return Icons.settings_input_hdmi;
      case EquipmentType.homeChargingStation:
        return Icons.ev_station;
      case EquipmentType.other:
        return Icons.category_outlined;
    }
  }

  Color _ownerTypeColor(EquipmentOwnerType type) {
    switch (type) {
      case EquipmentOwnerType.partner:
        return PsEvColors.blue;
      case EquipmentOwnerType.brand:
        return PsEvColors.amber;
      case EquipmentOwnerType.platform:
        return PsEvColors.emerald;
    }
  }

  void _showFullImage(BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 200,
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: const Text('Image failed to load'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestItem(BuildContext context, EquipmentListing listing) async {
    final app = context.read<AppState>();
    final auth = context.read<AuthService>();
    final partnerService = context.read<PartnerService>();

    final modeLabel = listing.mode == EquipmentMode.borrow ? 'borrow (refundable deposit)' : 'buy';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(listing.title),
        content: Text(
          'This will $modeLabel for ${listing.price.toStringAsFixed(0)} EGP'
          '${listing.mode == EquipmentMode.borrow ? ' (held now, refunded in full when you return it)' : ''}. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await partnerService.requestEquipment(
      listing: listing,
      driverId: app.currentUserId ?? '',
      driverName: auth.displayName,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request sent for ${listing.title}')));
  }

  Widget _listingThumbnail(EquipmentListing l) {
    if (l.imageUrl == null) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(color: PsEvColors.emeraldPale, borderRadius: BorderRadius.circular(12)),
        child: Icon(_iconFor(l.type), color: PsEvColors.emerald, size: 26),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        l.imageUrl!,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: 64,
            height: 64,
            color: PsEvColors.slate100,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: PsEvColors.emeraldPale, borderRadius: BorderRadius.circular(12)),
          child: Icon(_iconFor(l.type), color: PsEvColors.emerald, size: 26),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partnerService = context.watch<PartnerService>();
    final allListings = partnerService.listings;
    final listings = _typeFilter == null ? allListings : allListings.where((l) => l.type == _typeFilter).toList();
    final myRequests = partnerService.myEquipmentRequests;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('Available Equipment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
        ),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: _typeFilter == null,
                  onSelected: (_) => setState(() => _typeFilter = null),
                  label: const Text('All'),
                  selectedColor: PsEvColors.emerald,
                  labelStyle: TextStyle(
                    color: _typeFilter == null ? Colors.white : PsEvColors.slateText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: PsEvColors.slate100,
                ),
              ),
              ...EquipmentType.values.map((t) {
                final selected = _typeFilter == t;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selected,
                    onSelected: (_) => setState(() => _typeFilter = t),
                    avatar: Icon(_iconFor(t), size: 14, color: selected ? Colors.white : PsEvColors.mutedText),
                    label: Text(t.shortLabel),
                    selectedColor: PsEvColors.emerald,
                    labelStyle: TextStyle(color: selected ? Colors.white : PsEvColors.slateText, fontSize: 12, fontWeight: FontWeight.w600),
                    backgroundColor: PsEvColors.slate100,
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (listings.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No equipment listed in this category yet.', style: TextStyle(color: PsEvColors.mutedText)),
          )
        else
          ...listings.map((l) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: l.imageUrl == null ? null : () => _showFullImage(context, l.imageUrl!, l.title),
                        child: _listingThumbnail(l),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(l.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _ownerTypeColor(l.ownerType).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    l.ownerType.label,
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _ownerTypeColor(l.ownerType)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(l.description, style: const TextStyle(fontSize: 11, color: PsEvColors.mutedText)),
                            const SizedBox(height: 2),
                            Text(
                              '${l.mode == EquipmentMode.borrow ? "Borrow - deposit" : "Buy"}: ${l.price.toStringAsFixed(0)} EGP · Listed by ${l.ownerName}',
                              style: const TextStyle(fontSize: 11, color: PsEvColors.mutedText, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => _requestItem(context, l),
                                child: Text(l.mode == EquipmentMode.borrow ? 'Borrow' : 'Buy'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('My Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
        ),
        if (myRequests.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No equipment requests yet.', style: TextStyle(color: PsEvColors.mutedText)),
          )
        else
          ...myRequests.map((r) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.listingTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('${r.mode.name} · ${r.price.toStringAsFixed(0)} EGP', style: const TextStyle(fontSize: 11, color: PsEvColors.mutedText)),
                          ],
                        ),
                      ),
                      if (r.mode == EquipmentMode.borrow && r.status == EquipmentRequestStatus.fulfilled)
                        TextButton(
                          onPressed: () => context.read<PartnerService>().returnEquipment(r.id, driverId: r.driverId),
                          child: const Text('Mark Returned'),
                        )
                      else
                        PsEvStatusPill(
                          label: r.status.name,
                          background: PsEvColors.slate200,
                          textColor: PsEvColors.slateText,
                        ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }
}

// ===========================================================================
// Tab 2: Request Service (now second) - categorized: station / adaptor
// / cable / maintenance / other. City/Area now use the shared curated
// Egypt location list (LocationPickerField) instead of free text.
// ===========================================================================

class _ServiceRequestTab extends StatefulWidget {
  const _ServiceRequestTab();

  @override
  State<_ServiceRequestTab> createState() => _ServiceRequestTabState();
}

class _ServiceRequestTabState extends State<_ServiceRequestTab> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  ServiceCategory _category = ServiceCategory.station;
  String? _selectedCity;
  String? _selectedArea;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();

    // Pre-fill everything we already know about this driver:
    //   - Name and phone come straight from their EVPair account.
    //   - City/Area default to whatever they used on their MOST RECENT
    //     request of any category, if that value still exists in the
    //     curated location list (see isKnownGovernorate/isKnownArea
    //     inside LocationPickerField, which also guards this defensively).
    // All fields stay fully editable - these are just smart defaults.
    final auth = context.read<AuthService>();
    final partnerService = context.read<PartnerService>();

    final mostRecent = partnerService.myInstallRequests.isNotEmpty ? partnerService.myInstallRequests.first : null;

    _nameCtrl = TextEditingController(text: auth.displayName);
    _phoneCtrl = TextEditingController(text: auth.phone ?? '');
    _selectedCity = mostRecent?.city;
    _selectedArea = mostRecent?.area;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCity == null || _selectedArea == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a city and area.')),
      );
      return;
    }
    setState(() => _submitting = true);

    final app = context.read<AppState>();
    final partnerService = context.read<PartnerService>();

    await partnerService.submitInstallationRequest(
      driverId: app.currentUserId ?? '',
      driverName: _nameCtrl.text.trim(),
      driverPhone: _phoneCtrl.text.trim(),
      category: _category,
      city: _selectedCity!,
      area: _selectedArea!,
      addressDetails: _addressCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    _addressCtrl.clear();
    _notesCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Request submitted - a partner will accept it soon.')),
    );
  }

  Color _statusColor(InstallRequestStatus s) {
    switch (s) {
      case InstallRequestStatus.open:
        return PsEvColors.amber;
      case InstallRequestStatus.accepted:
        return PsEvColors.blue;
      case InstallRequestStatus.completed:
        return PsEvColors.emerald;
      case InstallRequestStatus.cancelled:
        return PsEvColors.mutedText;
    }
  }

  String _statusLabel(InstallRequestStatus s) {
    switch (s) {
      case InstallRequestStatus.open:
        return 'Waiting for a partner';
      case InstallRequestStatus.accepted:
        return 'Accepted';
      case InstallRequestStatus.completed:
        return 'Completed';
      case InstallRequestStatus.cancelled:
        return 'Cancelled';
    }
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final partnerService = context.watch<PartnerService>();
    final requests = partnerService.myInstallRequests;
    final dateFmt = DateFormat('MMM d, yyyy');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Request a Service', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  const Text(
                    'One of our installation partners will accept your request and contact you to schedule a visit.',
                    style: TextStyle(fontSize: 12, color: PsEvColors.mutedText),
                  ),
                  const SizedBox(height: 14),
                  const Text('What do you need?', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ServiceCategory.values.map((c) {
                      final selected = _category == c;
                      return ChoiceChip(
                        selected: selected,
                        onSelected: (_) => setState(() => _category = c),
                        avatar: Icon(_categoryIcon(c), size: 16, color: selected ? Colors.white : PsEvColors.mutedText),
                        label: Text(c.shortLabel),
                        selectedColor: PsEvColors.emerald,
                        labelStyle: TextStyle(color: selected ? Colors.white : PsEvColors.slateText, fontSize: 12, fontWeight: FontWeight.w600),
                        backgroundColor: PsEvColors.slate100,
                      );
                    }).toList(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 16),
                    child: Text(_category.description, style: const TextStyle(fontSize: 11, color: PsEvColors.emerald)),
                  ),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Your name'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Contact phone'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  LocationPickerField(
                    governorate: _selectedCity,
                    area: _selectedArea,
                    showAllOption: false,
                    userId: app.currentUserId ?? '',
                    userName: _nameCtrl.text.trim().isEmpty ? 'Driver' : _nameCtrl.text.trim(),
                    onGovernorateChanged: (v) => setState(() {
                      _selectedCity = v;
                      _selectedArea = null;
                    }),
                    onAreaChanged: (v) => setState(() => _selectedArea = v),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Address details (building, floor, parking spot)'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _category == ServiceCategory.other ? 'Describe what you need (required for Other)' : 'Notes (optional)',
                    ),
                    validator: (v) {
                      if (_category == ServiceCategory.other && (v == null || v.trim().isEmpty)) {
                        return 'Please describe what you need';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  PsEvFilledButton(
                    label: _submitting ? 'Submitting...' : 'Submit Request',
                    onTap: _submitting ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('My Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
        ),
        if (requests.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No requests yet.', style: TextStyle(color: PsEvColors.mutedText)),
          )
        else
          ...requests.map((r) => Card(
                margin: const EdgeInsets.only(bottom: 8),
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
                              Icon(_categoryIcon(r.category), size: 15, color: PsEvColors.emerald),
                              const SizedBox(width: 6),
                              Text(r.category.shortLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                          PsEvStatusPill(
                            label: _statusLabel(r.status),
                            background: _statusColor(r.status).withOpacity(0.12),
                            textColor: _statusColor(r.status),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${r.area}, ${r.city}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(r.addressDetails, style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                      Text(dateFmt.format(r.createdAt), style: const TextStyle(fontSize: 11, color: PsEvColors.mutedText)),
                      if (r.partnerName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Partner: ${r.partnerName}', style: const TextStyle(fontSize: 12, color: PsEvColors.emerald, fontWeight: FontWeight.w600)),
                        ),
                      if (r.status == InstallRequestStatus.open)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => context.read<PartnerService>().cancelInstallationRequest(r.id),
                            child: const Text('Cancel', style: TextStyle(color: PsEvColors.red, fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }
}
