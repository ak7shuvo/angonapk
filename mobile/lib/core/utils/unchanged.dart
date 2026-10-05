/// Marks a named argument as "leave as is", so that an explicit `null` can mean
/// "clear this value" (used by PATCH-style updates).
const Object unchanged = _Unchanged();

class _Unchanged {
  const _Unchanged();
}
