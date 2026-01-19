import { Injectable } from '@nestjs/common';
import { SuiService } from '../common/sui/sui.service';
import { UserProfileResponseDto } from './dto/user.dto';

@Injectable()
export class UsersService {
  constructor(private readonly suiService: SuiService) {}

  async getUserProfile(profileId: string): Promise<UserProfileResponseDto | null> {
    const response = await this.suiService.getObject(profileId);

    if (!response.data?.content || response.data.content.dataType !== 'moveObject') {
      return null;
    }

    const fields = response.data.content.fields as Record<string, unknown>;
    return this.mapUserFields(profileId, fields);
  }

  async getUserProfileByAddress(address: string): Promise<UserProfileResponseDto | null> {
    const response = await this.suiService.getOwnedObjects(address, 'users::UserProfile');

    if (response.data.length === 0) {
      return null;
    }

    const profileObj = response.data[0];
    if (!profileObj.data?.content || profileObj.data.content.dataType !== 'moveObject') {
      return null;
    }

    const fields = profileObj.data.content.fields as Record<string, unknown>;
    return this.mapUserFields(profileObj.data.objectId, fields);
  }

  async checkUsernameExists(username: string): Promise<boolean> {
    const response = await this.suiService.queryEvents('users::ProfileCreated');

    return response.data.some(
      (event) => (event.parsedJson as Record<string, unknown>)?.username === username,
    );
  }

  private mapUserFields(id: string, fields: Record<string, unknown>): UserProfileResponseDto {
    const stats = fields.stats as Record<string, unknown>;
    const reputation = fields.reputation as Record<string, unknown>;

    return {
      id,
      owner: fields.owner as string,
      username: fields.username as string | undefined,
      displayName: fields.display_name as string | undefined,
      bio: fields.bio as string | undefined,
      avatarUrl: fields.avatar_url as string | undefined,
      stats: {
        eventsCreated: Number(stats?.events_created || 0),
        eventsAttended: Number(stats?.events_attended || 0),
        ticketsPurchased: Number(stats?.tickets_purchased || 0),
        totalSpent: (stats?.total_spent as string) || '0',
      },
      reputation: {
        score: Number(reputation?.score || 0),
        eventsHosted: Number(reputation?.events_hosted || 0),
        attendanceRate: Number(reputation?.attendance_rate || 0),
        cancellations: Number(reputation?.cancellations || 0),
      },
      createdAt: fields.created_at as string,
      updatedAt: fields.updated_at as string,
    };
  }
}
