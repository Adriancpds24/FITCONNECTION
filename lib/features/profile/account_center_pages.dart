import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:rms/core/l10n/fitconnect_localizations.dart';
import 'package:rms/features/auth/password_policy.dart';
import 'package:rms/features/profile/account_center_service.dart';
import 'package:rms/features/profile/edit_profile_page.dart';
import 'package:rms/features/social/social_state.dart';
import 'package:rms/shared/themes/feed_palette.dart';

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = FitconnectLocalizations.of(context);
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(
          t.passwordAndSecurity,
          style: TextStyle(
            color: FeedPalette.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle(context, t.securitySectionLogin),
          _option(
            context,
            icon: Icons.key_outlined,
            title: t.securityChangePassword,
            subtitle: t.securitySubtitleChangePassword,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _ChangePasswordPage()),
            ),
          ),
          _option(
            context,
            icon: Icons.phonelink_lock_outlined,
            title: t.securityTwoFactor,
            subtitle: t.securitySubtitleTwoFactor,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _TwoFactorPage()),
            ),
          ),
          const SizedBox(height: 32),
          _sectionTitle(context, t.securitySectionAccount),
          _option(
            context,
            icon: Icons.devices_outlined,
            title: t.securitySessions,
            subtitle: t.securitySubtitleSessions,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _SessionsPage()),
            ),
          ),
          _option(
            context,
            icon: Icons.notifications_active_outlined,
            title: t.securityLoginAlerts,
            subtitle: t.securitySubtitleLoginAlerts,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _LoginAlertsPage()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Text(
        title,
        style: TextStyle(
          color: FeedPalette.text,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: FeedPalette.panelDecoration(radius: 20),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: FeedPalette.accent.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: FeedPalette.accent, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: FeedPalette.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: FeedPalette.muted, fontSize: 12),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: FeedPalette.muted,
        ),
      ),
    );
  }
}

class _ChangePasswordPage extends StatefulWidget {
  const _ChangePasswordPage();

  @override
  State<_ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<_ChangePasswordPage> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _svc = AccountCenterService();
  bool _loading = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final n = _next.text;
    final c = _confirm.text;
    if (n != c) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Las contraseñas nuevas no coinciden')),
      );
      return;
    }
    final err = validateStrongPassword(n);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _loading = true);
    try {
      await _svc.changePassword(
        currentPassword: _current.text,
        newPassword: n,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contraseña actualizada')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = FitconnectLocalizations.of(context);
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(t.securityChangePassword),
        backgroundColor: FeedPalette.background,
        foregroundColor: FeedPalette.text,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _current,
            obscureText: true,
            style: FeedPalette.bodyTextStyle,
            decoration: FeedPalette.textFieldDecoration(
              hint: 'Contraseña actual',
            ).copyWith(labelText: 'Contraseña actual'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _next,
            obscureText: true,
            style: FeedPalette.bodyTextStyle,
            decoration: FeedPalette.textFieldDecoration(
              hint: 'Nueva contraseña',
            ).copyWith(labelText: 'Nueva contraseña'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirm,
            obscureText: true,
            style: FeedPalette.bodyTextStyle,
            decoration: FeedPalette.textFieldDecoration(
              hint: 'Confirmar nueva',
            ).copyWith(labelText: 'Confirmar nueva'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

class _TwoFactorPage extends StatefulWidget {
  const _TwoFactorPage();

  @override
  State<_TwoFactorPage> createState() => _TwoFactorPageState();
}

class _TwoFactorPageState extends State<_TwoFactorPage> {
  final _svc = AccountCenterService();
  final _code = TextEditingController();
  final _disablePw = TextEditingController();
  bool _loading = true;
  bool _enabled = false;
  String? _secret32;
  String? _otpauth;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _disablePw.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await _svc.getSecuritySettings();
      if (!mounted) return;
      setState(() {
        _enabled = s['twoFactorEnabled'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _setup() async {
    setState(() => _loading = true);
    try {
      final r = await _svc.setupTwoFactor();
      if (!mounted) return;
      setState(() {
        _secret32 = r['secretBase32']?.toString();
        _otpauth = r['otpauthUrl']?.toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _confirm() async {
    setState(() => _loading = true);
    try {
      await _svc.confirmTwoFactor(_code.text.trim());
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _secret32 = null;
        _otpauth = null;
        _code.clear();
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('2FA activado')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _disable() async {
    setState(() => _loading = true);
    try {
      await _svc.disableTwoFactor(_disablePw.text);
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _disablePw.clear();
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('2FA desactivado')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = FitconnectLocalizations.of(context);
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(t.securityTwoFactor),
        backgroundColor: FeedPalette.background,
        foregroundColor: FeedPalette.text,
      ),
      body: _loading && _secret32 == null && !_enabled
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_enabled) ...[
                  const Text('2FA está activo en tu cuenta.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _disablePw,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña para desactivar',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _loading ? null : _disable,
                    child: const Text('Desactivar 2FA'),
                  ),
                ] else ...[
                  if (_secret32 == null)
                    FilledButton(
                      onPressed: _loading ? null : _setup,
                      child: const Text('Generar clave y continuar'),
                    ),
                  if (_secret32 != null) ...[
                    const Text(
                      'Añade esta clave en tu app de autenticación (Google Authenticator, etc.):',
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _secret32!,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (_otpauth != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: QrImageView(
                              data: _otpauth!,
                              version: QrVersions.auto,
                              size: 190,
                              backgroundColor: Colors.white,
                              gapless: true,
                              errorCorrectionLevel: QrErrorCorrectLevel.M,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        _otpauth!,
                        style:
                            TextStyle(fontSize: 11, color: FeedPalette.muted),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Código de 6 dígitos',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loading ? null : _confirm,
                      child: const Text('Confirmar y activar'),
                    ),
                  ],
                ],
              ],
            ),
    );
  }
}

class _SessionsPage extends StatefulWidget {
  const _SessionsPage();

  @override
  State<_SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<_SessionsPage> {
  final _svc = AccountCenterService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await _svc.listSessions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(int id) async {
    try {
      await _svc.revokeSession(id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sesión cerrada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = FitconnectLocalizations.of(context);
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(t.securitySessions),
        backgroundColor: FeedPalette.background,
        foregroundColor: FeedPalette.text,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final r = _rows[i];
                final id = (r['id'] as num).toInt();
                final ua = (r['userAgent'] ?? '').toString();
                final ip = (r['ipMasked'] ?? '').toString();
                final created = (r['createdAt'] ?? '').toString();
                return Card(
                  child: ListTile(
                    title: Text(ua.isEmpty ? 'Sesión' : ua, maxLines: 2),
                    subtitle: Text('$ip\n$created'),
                    trailing: IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: () => _revoke(id),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _LoginAlertsPage extends StatefulWidget {
  const _LoginAlertsPage();

  @override
  State<_LoginAlertsPage> createState() => _LoginAlertsPageState();
}

class _LoginAlertsPageState extends State<_LoginAlertsPage> {
  final _svc = AccountCenterService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _alertsOn = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final s = await _svc.getSecuritySettings();
      _alertsOn = s['loginAlertsEnabled'] != false;
      _rows = await _svc.listLoginAlerts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = FitconnectLocalizations.of(context);
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(t.securityLoginAlerts),
        backgroundColor: FeedPalette.background,
        foregroundColor: FeedPalette.text,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SwitchListTile(
                  title: const Text('Avisos de nuevo inicio de sesión'),
                  value: _alertsOn,
                  onChanged: (v) async {
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _alertsOn = v);
                    try {
                      await _svc.setLoginAlertsEnabled(v);
                    } catch (e) {
                      if (!mounted) return;
                      setState(() => _alertsOn = !v);
                      messenger.showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
                ),
                const Divider(),
                Expanded(
                  child: _rows.isEmpty
                      ? Center(
                          child: Text(FitconnectLocalizations.of(context)
                              .loginAlertsEmpty))
                      : ListView.builder(
                          itemCount: _rows.length,
                          itemBuilder: (context, i) {
                            final r = _rows[i];
                            return ListTile(
                              leading: const Icon(Icons.login),
                              title: Text((r['userAgent'] ?? '').toString()),
                              subtitle: Text(
                                '${r['ipMasked'] ?? ''} · ${r['createdAt'] ?? ''}',
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class PersonalDetailsPage extends StatelessWidget {
  const PersonalDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = FitconnectLocalizations.of(context);
    final user = SocialState().currentUser;
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(t.personalDetailsTitle),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
        foregroundColor: FeedPalette.text,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            t.personalDetailsBlurb,
            style: TextStyle(color: FeedPalette.muted),
          ),
          const SizedBox(height: 24),
          _tile(
            context,
            label: t.profilesLabel,
            value: user.username,
            icon: Icons.alternate_email,
            onTap: null,
          ),
          _tile(
            context,
            label: t.personalDetailsEditProfile,
            value: user.displayName,
            icon: Icons.edit_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProfilePage()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: FeedPalette.panelDecoration(radius: 20),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: FeedPalette.accent, size: 24),
        title: Text(label,
            style: TextStyle(color: FeedPalette.muted, fontSize: 12)),
        subtitle: Text(
          value,
          style: TextStyle(
            color: FeedPalette.text,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        trailing: onTap != null
            ? Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: FeedPalette.muted)
            : null,
      ),
    );
  }
}

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  final _svc = AccountCenterService();
  List<Map<String, dynamic>> _methods = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _methods = await _svc.listPaymentMethods();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAdd() async {
    final t = FitconnectLocalizations.of(context);
    final card = TextEditingController();
    final holder = TextEditingController();
    final month = TextEditingController();
    final year = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.paymentsAddMethod),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: card,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Número de tarjeta'),
              ),
              TextField(
                controller: holder,
                decoration: const InputDecoration(labelText: 'Titular'),
              ),
              TextField(
                controller: month,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Mes (1-12)'),
              ),
              TextField(
                controller: year,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Año (AAAA)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final em = int.tryParse(month.text);
    final ey = int.tryParse(year.text);
    if (em == null || ey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fecha inválida')),
      );
      return;
    }
    try {
      await _svc.addPaymentMethod(
        cardNumber: card.text,
        holderName: holder.text,
        expMonth: em,
        expYear: ey,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Método guardado (demo)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = FitconnectLocalizations.of(context);
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(t.paymentsTitle),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
        foregroundColor: FeedPalette.text,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  t.paymentsMethodsSection,
                  style: TextStyle(
                    color: FeedPalette.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                if (_methods.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: FeedPalette.panelDecoration(radius: 24),
                    child: Column(
                      children: [
                        Icon(Icons.credit_card_off_rounded,
                            size: 48, color: FeedPalette.muted),
                        const SizedBox(height: 16),
                        Text(
                          t.paymentsNoMethods,
                          style: TextStyle(
                            color: FeedPalette.text,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.paymentsNoMethodsHint,
                          style:
                              TextStyle(color: FeedPalette.muted, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _openAdd,
                          style: FeedPalette.primaryButtonStyle(radius: 12),
                          child: Text(t.paymentsAddMethod),
                        ),
                      ],
                    ),
                  )
                else ...[
                  ..._methods.map(
                    (m) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: FeedPalette.panelDecoration(radius: 16),
                      child: ListTile(
                        leading:
                            Icon(Icons.credit_card, color: FeedPalette.accent),
                        title: Text('${m['brand']} ···· ${m['last4']}'),
                        subtitle: Text(
                          '${m['holderName'] ?? ''} · ${m['expMonth']}/${m['expYear']}',
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _openAdd,
                    style: FeedPalette.primaryButtonStyle(radius: 12),
                    child: Text(t.paymentsAddMethod),
                  ),
                ],
                const SizedBox(height: 32),
                Text(
                  t.paymentsHistorySection,
                  style: TextStyle(
                    color: FeedPalette.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                _historyTile(
                    Icons.receipt_long_outlined, t.paymentsHistoryOrders),
                _historyTile(
                    Icons.subscriptions_outlined, t.paymentsSubscriptions),
              ],
            ),
    );
  }

  Widget _historyTile(IconData icon, String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: FeedPalette.panelDecoration(radius: 20),
      child: ListTile(
        leading: Icon(icon, color: FeedPalette.accent),
        title: Text(title,
            style: TextStyle(
                color: FeedPalette.text, fontWeight: FontWeight.bold)),
        trailing: Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: FeedPalette.muted),
        onTap: () {},
      ),
    );
  }
}
