import { Injectable, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';

@Injectable()
export class SuiService implements OnModuleInit {
  private client: SuiClient;
  private packageId: string;

  constructor(private configService: ConfigService) {}

  onModuleInit() {
    const network = this.configService.get<string>('sui.network') as
      | 'devnet'
      | 'testnet'
      | 'mainnet';
    this.packageId = this.configService.get<string>('sui.packageId') || '0x0';
    this.client = new SuiClient({ url: getFullnodeUrl(network) });
  }

  getClient(): SuiClient {
    return this.client;
  }

  getPackageId(): string {
    return this.packageId;
  }

  async getObject(objectId: string) {
    return this.client.getObject({
      id: objectId,
      options: {
        showContent: true,
        showType: true,
        showOwner: true,
      },
    });
  }

  async getOwnedObjects(owner: string, type?: string) {
    const filter = type
      ? { StructType: `${this.packageId}::${type}` }
      : undefined;

    return this.client.getOwnedObjects({
      owner,
      filter,
      options: {
        showContent: true,
        showType: true,
      },
    });
  }

  async queryEvents(eventType: string, cursor?: string, limit = 50) {
    return this.client.queryEvents({
      query: { MoveEventType: `${this.packageId}::${eventType}` },
      cursor: cursor ? { txDigest: cursor, eventSeq: '0' } : undefined,
      limit,
      order: 'descending',
    });
  }

  async getDynamicFields(parentId: string) {
    return this.client.getDynamicFields({
      parentId,
    });
  }

  async getDynamicFieldObject(parentId: string, name: { type: string; value: unknown }) {
    return this.client.getDynamicFieldObject({
      parentId,
      name,
    });
  }
}
