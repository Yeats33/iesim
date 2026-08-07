/// IO 与网络操作的统一返回类型（spec §7）。
///
/// 领域代码不抛裸异常穿透到 UI 层；可预期的失败一律以 Result 返回，
/// UI 按失败类型给出可操作提示。本计划引入 [StoreError]，计划 4 扩展
/// WebDAV 相关失败子类型。
sealed class Result<T> {
  const Result();
}

/// 成功，携带 [value]。
class Ok<T> extends Result<T> {
  final T value;

  const Ok(this.value);
}

/// 失败，携带可辨识的 [failure]。
class Err<T> extends Result<T> {
  final Failure failure;

  const Err(this.failure);
}

/// 可预期的失败根类型。
sealed class Failure {
  const Failure();
}

/// 本地持久化失败（磁盘错误、约束违反等）。
class StoreError extends Failure {
  final String message;

  const StoreError(this.message);

  @override
  String toString() => 'StoreError($message)';
}
