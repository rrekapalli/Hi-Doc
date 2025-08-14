import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Center(
        child: auth.isLoading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Hi-Doc Login', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 32),
                  if (auth.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(auth.error!, style: const TextStyle(color: Colors.red)),
                    ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.account_circle),
                    label: const Text('Continue with Google'),
                    onPressed: () => auth.signInGoogle(),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.business),
                    label: const Text('Continue with Microsoft'),
                    onPressed: () => auth.signInMicrosoft(),
                  ),
                ],
              ),
      ),
    );
  }
}
