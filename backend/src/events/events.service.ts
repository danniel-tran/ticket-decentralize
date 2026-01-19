import { Injectable } from '@nestjs/common';
import { SuiService } from '../common/sui/sui.service';
import { EventResponseDto } from './dto/event.dto';

const STATUS_MAP: Record<number, string> = {
  0: 'draft',
  1: 'open',
  2: 'in_progress',
  3: 'completed',
  4: 'cancelled',
};

@Injectable()
export class EventsService {
  constructor(private readonly suiService: SuiService) {}

  async getEvent(eventId: string): Promise<EventResponseDto | null> {
    const response = await this.suiService.getObject(eventId);

    if (!response.data?.content || response.data.content.dataType !== 'moveObject') {
      return null;
    }

    const fields = response.data.content.fields as Record<string, unknown>;
    return this.mapEventFields(eventId, fields);
  }

  async getEventsByOrganizer(organizer: string): Promise<EventResponseDto[]> {
    const response = await this.suiService.queryEvents(
      'events::EventCreated',
    );

    const organizerEvents = response.data.filter(
      (event) => (event.parsedJson as Record<string, unknown>)?.organizer === organizer,
    );

    const events: EventResponseDto[] = [];
    for (const event of organizerEvents) {
      const eventId = (event.parsedJson as Record<string, unknown>)?.event_id as string;
      if (eventId) {
        const eventData = await this.getEvent(eventId);
        if (eventData) {
          events.push(eventData);
        }
      }
    }

    return events;
  }

  async getRecentEvents(limit = 20): Promise<EventResponseDto[]> {
    const response = await this.suiService.queryEvents(
      'events::EventCreated',
      undefined,
      limit,
    );

    const events: EventResponseDto[] = [];
    for (const event of response.data) {
      const eventId = (event.parsedJson as Record<string, unknown>)?.event_id as string;
      if (eventId) {
        const eventData = await this.getEvent(eventId);
        if (eventData) {
          events.push(eventData);
        }
      }
    }

    return events;
  }

  private mapEventFields(id: string, fields: Record<string, unknown>): EventResponseDto {
    const metadata = fields.metadata as Record<string, unknown>;
    const config = fields.config as Record<string, unknown>;
    const stats = fields.stats as Record<string, unknown>;

    return {
      id,
      organizer: fields.organizer as string,
      metadata: {
        title: metadata?.title as string,
        description: metadata?.description as string,
        walrusBlobId: metadata?.walrus_blob_id as string,
        imageUrl: metadata?.image_url as string,
        category: metadata?.category as string,
        tags: (metadata?.tags as string[]) || [],
      },
      config: {
        startTime: config?.start_time as string,
        endTime: config?.end_time as string,
        registrationDeadline: config?.registration_deadline as string,
        capacity: Number(config?.capacity),
        ticketPrice: config?.ticket_price as string,
        requiresApproval: config?.requires_approval as boolean,
        isTransferable: config?.is_transferable as boolean,
        refundDeadline: config?.refund_deadline as string,
      },
      stats: {
        registered: Number(stats?.registered),
        attended: Number(stats?.attended),
        revenue: stats?.revenue as string,
        refunded: stats?.refunded as string,
      },
      status: STATUS_MAP[fields.status as number] || 'unknown',
      createdAt: fields.created_at as string,
      updatedAt: fields.updated_at as string,
    };
  }
}
