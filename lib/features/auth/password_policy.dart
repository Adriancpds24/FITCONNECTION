String? validateStrongPassword(String password) {
  if (password.length < 8) {
    return 'La contrasena debe tener al menos 8 caracteres.';
  }

  if (!RegExp(r'[a-z]').hasMatch(password)) {
    return 'La contrasena debe incluir al menos una minuscula.';
  }

  if (!RegExp(r'[A-Z]').hasMatch(password)) {
    return 'La contrasena debe incluir al menos una mayuscula.';
  }

  if (!RegExp(r'[0-9]').hasMatch(password)) {
    return 'La contrasena debe incluir al menos un numero.';
  }

  if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
    return 'La contrasena debe incluir al menos un simbolo.';
  }

  return null;
}
