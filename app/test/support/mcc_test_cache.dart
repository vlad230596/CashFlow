import 'package:cashflow/services/mcc_cache_store.dart';

/// Widget/unit tests never access the native application support directory.
MccCacheStore isolatedMccCache() => MccCacheStore(storage: MemoryMccStorage());
