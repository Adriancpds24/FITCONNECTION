import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Spanish/English UI strings (no codegen). Uses [Locale.languageCode]; defaults to English.
class FitconnectLocalizations {
  FitconnectLocalizations(this.locale);

  final Locale locale;

  static FitconnectLocalizations of(BuildContext context) {
    return Localizations.of<FitconnectLocalizations>(
          context,
          FitconnectLocalizations,
        ) ??
        FitconnectLocalizations(Localizations.localeOf(context));
  }

  static const LocalizationsDelegate<FitconnectLocalizations> delegate =
      _FitconnectLocalizationsDelegate();

  bool get _es => locale.languageCode.startsWith('es');

  String get chatOnlineNow => _es ? 'En línea ahora' : 'Online now';
  String get chatStartHistory => _es
      ? 'Este es el comienzo de tu historial de chat'
      : 'This is the beginning of your chat history';
  String get chatMessageHint => _es ? 'Mensaje…' : 'Message…';
  String get chatSend => _es ? 'Enviar' : 'Send';
  String chatCallMockBody(String name) => _es
      ? 'Conectando una llamada de demostración con $name'
      : 'Connecting a demo call with $name';
  String get chatCallMockTitle => _es ? 'Iniciando llamada' : 'Starting call';
  String get chatMoreTitle => _es ? 'Opciones del chat' : 'Chat options';
  String get chatMoreViewProfile => _es ? 'Ver perfil' : 'View profile';
  String get chatMoreMute =>
      _es ? 'Silenciar notificaciones (demo)' : 'Mute notifications (demo)';
  String get chatMutedSnack => _es
      ? 'Chat silenciado para esta conversación.'
      : 'This conversation is muted.';
  String get chatMoreDeleteConversation =>
      _es ? 'Eliminar conversación' : 'Delete conversation';
  String get chatDeleteConversationTitle =>
      _es ? 'Eliminar conversación' : 'Delete conversation';
  String get chatDeleteConversationBody => _es
      ? 'Se borrará de tu lista de chats. Si vuelves a escribir, la conversación reaparecerá.'
      : 'It will be removed from your chat list. If you message again, the conversation will reappear.';
  String get chatDeleteConversationDone =>
      _es ? 'Conversación eliminada.' : 'Conversation deleted.';
  String get chatDeleteConversationError => _es
      ? 'No se pudo eliminar la conversación.'
      : 'Could not delete the conversation.';

  String get notificationAccept => _es ? 'Aceptar' : 'Accept';
  String get notificationReject => _es ? 'Rechazar' : 'Decline';

  String get accountCenterTitle => _es ? 'Centro de cuentas' : 'Account center';
  String get accountCenterSubtitle => _es
      ? 'Administra tus experiencias conectadas en FitConnect.'
      : 'Manage your connected experiences in FitConnect.';
  String get passwordAndSecurity =>
      _es ? 'Contraseña y seguridad' : 'Password and security';
  String get securitySectionLogin =>
      _es ? 'Inicio de sesión y recuperación' : 'Login and recovery';
  String get securitySectionAccount =>
      _es ? 'Seguridad de la cuenta' : 'Account security';
  String get securityChangePassword =>
      _es ? 'Cambiar contraseña' : 'Change password';
  String get securitySubtitleChangePassword => _es
      ? 'Se recomienda usar una contraseña fuerte que no uses en otros sitios.'
      : 'Use a strong password that you don\'t reuse on other sites.';
  String get securityTwoFactor =>
      _es ? 'Autenticación en dos pasos' : 'Two-step authentication';
  String get securitySubtitleTwoFactor => _es
      ? 'Añade una capa extra de seguridad a tu cuenta.'
      : 'Add an extra layer of security to your account.';
  String get securitySessions =>
      _es ? 'Dónde has iniciado sesión' : 'Where you\'re logged in';
  String get securitySubtitleSessions => _es
      ? 'Revisa los dispositivos activos con tu cuenta.'
      : 'Review active devices signed in to your account.';
  String get securityLoginAlerts =>
      _es ? 'Alertas de inicio de sesión' : 'Login alerts';
  String get securitySubtitleLoginAlerts => _es
      ? 'Te avisaremos si detectamos un inicio de sesión sospechoso.'
      : 'We\'ll notify you if we detect a suspicious sign-in.';

  String get personalDetailsTitle =>
      _es ? 'Datos personales' : 'Personal details';
  String get personalDetailsBlurb => _es
      ? 'FitConnect usa esta información para mantener tu cuenta segura y mejorar tu experiencia.'
      : 'FitConnect uses this information to keep your account safe and improve your experience.';
  String get personalDetailsEditProfile =>
      _es ? 'Editar perfil y foto' : 'Edit profile and photo';
  String get profilesLabel => _es ? 'Perfiles' : 'Profiles';

  String get paymentsTitle => _es ? 'Pagos' : 'Payments';
  String get paymentsAddMethod =>
      _es ? 'Añadir método de pago' : 'Add payment method';
  String get paymentsNoMethods => _es
      ? 'No tienes métodos de pago guardados'
      : 'You have no saved payment methods';
  String get paymentsNoMethodsHint => _es
      ? 'Añade un método de pago para realizar compras en FitConnect.'
      : 'Add a payment method for future FitConnect purchases.';
  String get paymentsMethodsSection =>
      _es ? 'Métodos de pago' : 'Payment methods';
  String get paymentsHistorySection => _es ? 'Historial' : 'History';
  String get paymentsHistoryOrders =>
      _es ? 'Historial de pedidos' : 'Order history';
  String get paymentsSubscriptions =>
      _es ? 'Suscripciones activas' : 'Active subscriptions';

  String get nutritionMetricsLoadError => _es
      ? 'No se pudo cargar tu plan nutricional desde el servidor.'
      : 'Could not load your nutrition plan from the server.';

  String get profileRestrictedBlocked =>
      _es ? 'No puedes ver este perfil' : 'You cannot view this profile';
  String get profileRestrictedBlockedHint => _es
      ? 'Esta cuenta tiene el acceso restringido.'
      : 'This account has restricted access.';

  String get loginAlertsEmpty => _es
      ? 'Aún no hay registros de inicio de sesión.'
      : 'No sign-in history yet.';

  String get accountSettingsHeader =>
      _es ? 'Configuración de la cuenta' : 'Account settings';
  String get accountSettingsFooter => _es
      ? 'Administra la configuración de tus cuentas para todas las apps de FitConnect.'
      : 'Manage your account settings for all FitConnect apps.';
}

class _FitconnectLocalizationsDelegate
    extends LocalizationsDelegate<FitconnectLocalizations> {
  const _FitconnectLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<FitconnectLocalizations> load(Locale locale) {
    return SynchronousFuture(FitconnectLocalizations(locale));
  }

  @override
  bool shouldReload(
          covariant LocalizationsDelegate<FitconnectLocalizations> old) =>
      false;
}
