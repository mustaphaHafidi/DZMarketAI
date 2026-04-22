enum CourierCredentialStatus { unknown, valid, invalid }

CourierCredentialStatus courierCredentialStatusFromValue(Object? raw) {
  final value = raw?.toString().trim().toLowerCase() ?? '';
  switch (value) {
    case 'valid':
      return CourierCredentialStatus.valid;
    case 'invalid':
      return CourierCredentialStatus.invalid;
    default:
      return CourierCredentialStatus.unknown;
  }
}
