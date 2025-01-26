import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Login'.tr(),
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  LoginPageState createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  bool _agreeToPrivacy = false;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  void _submitForm() {
    if (_formKey.currentState?.validate() == true && _agreeToPrivacy) {
      _formKey.currentState?.save();
      debugPrint('Form is valid and privacy policy agreed to.');
      final loginForm = _formKey.currentState as FormState;
      final username = _usernameController.text;
final password = _passwordController.text;
      debugPrint('Username: $username');
      debugPrint('Password: $password');
      final loginInfo = [username, password];
      debugPrint('Login Form: $loginForm');
      Navigator.pop(context, loginInfo);
    } else {
      debugPrint('Form is invalid or privacy policy not agreed to.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Login Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: 'Username'.tr()),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your username'.tr();
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'.tr()),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password'.tr();
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Checkbox(
                    value: _agreeToPrivacy,
                    onChanged: (bool? value) {
                      setState(() {
                        _agreeToPrivacy = value ?? false;
                      });
                    },
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        // Open privacy policy link
                      },
                      child: Text(
                        'I agree to the Privacy Policy'.tr(),
                        style: TextStyle(
                          decoration: TextDecoration.underline,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Center(
                child: ElevatedButton(
                  onPressed: _submitForm,
                  child: Text('Login').tr(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
