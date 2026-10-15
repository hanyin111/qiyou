import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import asset from '@ohos.security.asset';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';

class VaultIndex {
  generation: string = '';
  chunks: number = 0;
}

export default class QiyouDevicePlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private tail: Promise<void> = Promise.resolve();
  private readonly indexAlias: string = 'app.qiyou.vault.index.v1';

  getUniqueClassName(): string { return 'QiyouDevicePlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'app.qiyou/device');
    this.channel.setMethodCallHandler(this);
  }
  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    // Serialize read/write/clear to keep manifest commits ordered.
    this.tail = this.tail.then(async () => {
      if (call.method === 'read') { result.success(await this.read()); }
      else if (call.method === 'write') {
        await this.write(call.args as string); result.success(null);
      } else if (call.method === 'delete') {
        await this.clear(); result.success(null);
      } else { result.notImplemented(); }
    }).catch(() => { result.error('SECURE_STORAGE', '本机安全存储不可用', null); });
  }
  private encode(value: string): Uint8Array { return new util.TextEncoder().encodeInto(value); }
  private decode(value: Uint8Array): string { return util.TextDecoder.create('utf-8').decodeWithStream(value); }
  private async secret(alias: string): Promise<Uint8Array | null> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.encode(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const found = await asset.query(query);
      return found.length === 0 ? null : found[0].get(asset.Tag.SECRET) as Uint8Array;
    } catch (error) {
      if ((error as BusinessError).code === 24000002) { return null; }
      throw new Error('Secure storage query failed');
    }
  }
  private async save(alias: string, bytes: Uint8Array): Promise<void> {
    const item: asset.AssetMap = new Map();
    item.set(asset.Tag.ALIAS, this.encode(alias));
    item.set(asset.Tag.SECRET, bytes);
    item.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
    item.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    // Do not use IS_PERSISTENT: credentials must be removed on uninstall.
    await asset.add(item);
  }
  private async remove(alias: string): Promise<void> {
    const query: asset.AssetMap = new Map(); query.set(asset.Tag.ALIAS, this.encode(alias));
    try { await asset.remove(query); }
    catch (error) {
      if ((error as BusinessError).code !== 24000002) { throw new Error('Secure storage delete failed'); }
    }
  }
  private async index(): Promise<VaultIndex | null> {
    const bytes = await this.secret(this.indexAlias);
    if (bytes === null) { return null; }
    const value = JSON.parse(this.decode(bytes)) as VaultIndex;
    if (value.chunks < 0 || value.chunks > 570 || value.generation.length > 80) { throw new Error('Invalid vault'); }
    return value;
  }
  private chunkAlias(index: VaultIndex, number: number): string {
    return `app.qiyou.vault.${index.generation}.${number}`;
  }
  private async read(): Promise<string | null> {
    const index = await this.index(); if (index === null) { return null; }
    const chunks: Uint8Array[] = []; let size = 0;
    for (let i = 0; i < index.chunks; i++) {
      const bytes = await this.secret(this.chunkAlias(index, i));
      if (bytes === null) { throw new Error('Incomplete vault'); }
      chunks.push(bytes); size += bytes.length;
    }
    if (size > 512000) { throw new Error('Vault exceeds limit'); }
    const joined = new Uint8Array(size); let offset = 0;
    for (const bytes of chunks) { joined.set(bytes, offset); offset += bytes.length; }
    return this.decode(joined);
  }
  private async cleanup(index: VaultIndex): Promise<void> {
    for (let i = 0; i < index.chunks; i++) { await this.remove(this.chunkAlias(index, i)); }
  }
  private async write(value: string): Promise<void> {
    const bytes = this.encode(value);
    if (bytes.length === 0 || bytes.length > 512000) { throw new Error('Invalid vault size'); }
    const previous = await this.index();
    const next = new VaultIndex();
    next.generation = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
    next.chunks = Math.ceil(bytes.length / 900);
    try {
      // Asset Store limits SECRET to 1024 bytes. Commit the index only after
      // every 900-byte chunk has been stored successfully.
      for (let i = 0; i < next.chunks; i++) {
        await this.save(this.chunkAlias(next, i), bytes.slice(i * 900, (i + 1) * 900));
      }
      await this.save(this.indexAlias, this.encode(JSON.stringify(next)));
    } catch (_) {
      try { await this.cleanup(next); } catch (_) { /* Encrypted orphan chunks remain isolated. */ }
      throw new Error('Vault commit failed');
    }
    if (previous !== null) {
      try { await this.cleanup(previous); } catch (_) { /* New manifest is already committed. */ }
    }
  }
  private async clear(): Promise<void> {
    const previous = await this.index();
    await this.remove(this.indexAlias);
    if (previous !== null) { await this.cleanup(previous); }
  }
}
