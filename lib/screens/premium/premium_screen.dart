import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../core/api_client.dart';

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    final api = ApiClient();
    return Scaffold(
      appBar: AppBar(title: const Text('Go Premium')),
      body: SafeArea(
        child: FutureBuilder<List<dynamic>>(
          future: api.getPlans(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final plans = snap.data!;
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Unlock full IELTS prep', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  const ListTile(leading: Icon(Icons.all_inclusive), title: Text('Unlimited access to premium practice sets')),
                  const ListTile(leading: Icon(Icons.assignment_turned_in), title: Text('Full exam simulations')),
                  const ListTile(leading: Icon(Icons.insights), title: Text('Advanced progress tracking')),
                  const Spacer(),
                  for (final p in plans) ...[
                    Card(
                      child: ListTile(
                        title: Text(p['name'] ?? 'Plan'),
                        subtitle: Text('${p['currency']} ${(p['price_cents'] / 100).toStringAsFixed(2)} / ${p['billing_interval']}'),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            final session = await api.createPaymentSession(p['id']);
                            if (!context.mounted) return;
                            Navigator.push(context, MaterialPageRoute(builder: (_) => CheckoutScreen(session: session)));
                          },
                          child: const Text('Continue'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Maybe later')),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class CheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> session;
  const CheckoutScreen({super.key, required this.session});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _card = TextEditingController();
  final _exp = TextEditingController();
  final _cvc = TextEditingController();
  final api = ApiClient();
  final _formKey = GlobalKey<FormState>();
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    final planText = '${widget.session['currency']} ${(widget.session['amount_cents'] / 100).toStringAsFixed(2)}';
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout (demo)')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plan amount: $planText'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _card,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Card number (demo)'),
                  validator: (v) {
                    final digits = v?.replaceAll(' ', '') ?? '';
                    if (digits.length != 16 || int.tryParse(digits) == null) return 'Enter 16-digit card number';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _exp,
                      decoration: const InputDecoration(labelText: 'MM/YY'),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        final reg = RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$');
                        if (!reg.hasMatch(value)) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _cvc,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'CVC'),
                      validator: (v) => v != null && RegExp(r'^\d{3}$').hasMatch(v) ? null : '3 digits',
                    ),
                  ),
                ]),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _processing
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) return;
                            setState(() => _processing = true);
                            try {
                              await api.confirmPaymentSession(widget.session['id']);
                              app.setPremium(true);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment successful. Premium activated.')));
                              Navigator.popUntil(context, ModalRoute.withName('/shell'));
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
                            } finally {
                              if (mounted) setState(() => _processing = false);
                            }
                          },
                    child: _processing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Pay now (demo)'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
