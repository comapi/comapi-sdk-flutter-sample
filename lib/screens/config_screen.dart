import 'package:flutter/material.dart';
import 'package:dotdigital_push/dotdigital_push.dart';
import '../services/notification_service.dart';
import '../theme/dotdigital_brand.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _apiSpaceIdController;
  late TextEditingController _sharedSecretController;
  late TextEditingController _issuerController;
  late TextEditingController _audienceController;
  late TextEditingController _userIdController;
  late TextEditingController _emailController;
  late TextEditingController _backendAuthUrlController;

  bool _obscureSecret = true;

  @override
  void initState() {
    super.initState();
    final config = NotificationService().config;
    _apiSpaceIdController = TextEditingController(text: config.apiSpaceId);
    _sharedSecretController = TextEditingController(text: config.sharedSecret ?? '');
    _issuerController = TextEditingController(text: config.issuer);
    _audienceController = TextEditingController(text: config.audience);
    _userIdController = TextEditingController(text: config.userId);
    _emailController = TextEditingController(text: config.contactEmail ?? '');
    _backendAuthUrlController = TextEditingController(text: config.backendAuthUrl ?? '');
  }

  @override
  void dispose() {
    _apiSpaceIdController.dispose();
    _sharedSecretController.dispose();
    _issuerController.dispose();
    _audienceController.dispose();
    _userIdController.dispose();
    _emailController.dispose();
    _backendAuthUrlController.dispose();
    super.dispose();
  }

  /// Validates and saves the Dotdigital configuration.
  void _saveConfig() async {
    if (_formKey.currentState!.validate()) {
      final newConfig = DotdigitalConfig(
        apiSpaceId: _apiSpaceIdController.text.trim(),
        sharedSecret: _sharedSecretController.text.trim().isEmpty ? null : _sharedSecretController.text.trim(),
        issuer: _issuerController.text.trim().isEmpty ? 'https://api.comapi.com/defaultauth' : _issuerController.text.trim(),
        audience: _audienceController.text.trim().isEmpty ? 'https://api.comapi.com' : _audienceController.text.trim(),
        userId: _userIdController.text.trim().isEmpty ? 'flutter_user_001' : _userIdController.text.trim(),
        contactEmail: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        backendAuthUrl: _backendAuthUrlController.text.trim().isEmpty ? null : _backendAuthUrlController.text.trim(),
      );

      final success = await NotificationService().saveConfiguration(newConfig);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
              ? NotificationService().restartRequired
                ? 'Configuration saved. Restart the app to use the new API space.'
                : 'Configuration saved.'
              : 'Configuration failed: ${NotificationService().lifecycleError}'),
          ),
        );
        if (success) Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credentials & Config'),
        backgroundColor: DotdigitalBrand.inkBlack,
        foregroundColor: DotdigitalBrand.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveConfig,
            tooltip: 'Save Configuration',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: DotdigitalBrand.coralStep4,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: DotdigitalBrand.coralStep1, width: 1.5),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: DotdigitalBrand.inkBlack, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SECURITY NOTICE (EXAMPLE ONLY)',
                            style: DotdigitalBrand.eyebrowStyle(fontSize: 10, color: DotdigitalBrand.inkBlack),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Client-side Shared Secret storage and JWT signing are implemented here strictly for example and documentation validation purposes. In production apps, never embed your shared secret in client code. Request tokens from your backend server.',
                            style: DotdigitalBrand.bodyStyle(fontSize: 12, color: DotdigitalBrand.inkBlack),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: DotdigitalBrand.signalPink,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: DotdigitalBrand.electricPink, width: 1),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: DotdigitalBrand.inkBlack),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Configure credentials from your Dotdigital Marketing Push Notification Profile to link devices and register contacts.',
                        style: DotdigitalBrand.bodyStyle(fontSize: 13, color: DotdigitalBrand.inkBlack),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'AUTHENTICATION',
                style: DotdigitalBrand.eyebrowStyle(fontSize: 10, color: DotdigitalBrand.darkSand),
              ),
              const SizedBox(height: 4),
              Text(
                'Push Notification Profile Credentials',
                style: DotdigitalBrand.headerStyle(fontSize: 20),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _apiSpaceIdController,
                decoration: const InputDecoration(
                  labelText: 'API Space ID *',
                  hintText: 'e.g. 5a1b2c3d-4e5f-6a7b-8c9d-0e1f2a3b4c5d',
                  prefixIcon: Icon(Icons.hub_outlined, color: DotdigitalBrand.inkBlack),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'API Space ID is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _sharedSecretController,
                obscureText: _obscureSecret,
                decoration: InputDecoration(
                  labelText: 'Shared Secret (for local JWT challenge signing)',
                  hintText: 'Secret from Dotdigital Push Profile',
                  prefixIcon: const Icon(Icons.key_outlined, color: DotdigitalBrand.inkBlack),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureSecret ? Icons.visibility : Icons.visibility_off,
                      color: DotdigitalBrand.inkBlack,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureSecret = !_obscureSecret;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _issuerController,
                      decoration: const InputDecoration(
                        labelText: 'Issuer (iss claim)',
                        prefixIcon: Icon(Icons.security_outlined, color: DotdigitalBrand.inkBlack),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _audienceController,
                      decoration: const InputDecoration(
                        labelText: 'Audience (aud claim)',
                        prefixIcon: Icon(Icons.group_work_outlined, color: DotdigitalBrand.inkBlack),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Text(
                'AUDIENCE DISCOVERY',
                style: DotdigitalBrand.eyebrowStyle(fontSize: 10, color: DotdigitalBrand.darkSand),
              ),
              const SizedBox(height: 4),
              Text(
                'User Profile & Contact Discovery',
                style: DotdigitalBrand.headerStyle(fontSize: 20),
              ),
              const SizedBox(height: 6),
              Text(
                'Dotdigital discovers contacts only when both an email address AND a device push token are attached to the push profile.',
                style: DotdigitalBrand.bodyStyle(fontSize: 13, color: DotdigitalBrand.charcoal),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _userIdController,
                decoration: const InputDecoration(
                  labelText: 'User ID (sub claim) *',
                  hintText: 'e.g. user_12345 or persistent device GUID',
                  prefixIcon: Icon(Icons.badge_outlined, color: DotdigitalBrand.inkBlack),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'User ID is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Contact Email Address',
                  hintText: 'e.g. customer@example.com',
                  prefixIcon: Icon(Icons.email_outlined, color: DotdigitalBrand.inkBlack),
                  helperText: 'Required to populate PUSHOPTIN_xxx in Dotdigital',
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'PRODUCTION ARCHITECTURE',
                style: DotdigitalBrand.eyebrowStyle(fontSize: 10, color: DotdigitalBrand.darkSand),
              ),
              const SizedBox(height: 4),
              Text(
                'Optional Remote Authentication',
                style: DotdigitalBrand.headerStyle(fontSize: 20),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _backendAuthUrlController,
                decoration: const InputDecoration(
                  labelText: 'Backend Auth URL (Optional)',
                  hintText: 'https://api.yourdomain.com/push-auth-token',
                  prefixIcon: Icon(Icons.cloud_outlined, color: DotdigitalBrand.inkBlack),
                  helperText: 'For production architectures where backend issues signed JWTs',
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _saveConfig,
                  icon: const Icon(Icons.save),
                  label: const Text('Save & Apply Configuration'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DotdigitalBrand.electricPink,
                    foregroundColor: DotdigitalBrand.inkBlack,
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
