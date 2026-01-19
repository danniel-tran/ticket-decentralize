import { Injectable } from '@nestjs/common';
import { SuiService } from '../common/sui/sui.service';
import { TicketResponseDto, ValidateTicketResponseDto } from './dto/ticket.dto';

@Injectable()
export class TicketsService {
  constructor(private readonly suiService: SuiService) {}

  async getTicket(ticketId: string): Promise<TicketResponseDto | null> {
    const response = await this.suiService.getObject(ticketId);

    if (!response.data?.content || response.data.content.dataType !== 'moveObject') {
      return null;
    }

    const fields = response.data.content.fields as Record<string, unknown>;
    return this.mapTicketFields(ticketId, fields);
  }

  async getTicketsByOwner(owner: string): Promise<TicketResponseDto[]> {
    const response = await this.suiService.getOwnedObjects(owner, 'tickets::Ticket');

    const tickets: TicketResponseDto[] = [];
    for (const obj of response.data) {
      if (obj.data?.content && obj.data.content.dataType === 'moveObject') {
        const fields = obj.data.content.fields as Record<string, unknown>;
        const ticketId = obj.data.objectId;
        tickets.push(this.mapTicketFields(ticketId, fields));
      }
    }

    return tickets;
  }

  async getTicketsByEvent(eventId: string): Promise<TicketResponseDto[]> {
    const response = await this.suiService.queryEvents('tickets::TicketPurchased');

    const eventTickets = response.data.filter(
      (event) => (event.parsedJson as Record<string, unknown>)?.event_id === eventId,
    );

    const tickets: TicketResponseDto[] = [];
    for (const event of eventTickets) {
      const ticketId = (event.parsedJson as Record<string, unknown>)?.ticket_id as string;
      if (ticketId) {
        const ticket = await this.getTicket(ticketId);
        if (ticket) {
          tickets.push(ticket);
        }
      }
    }

    return tickets;
  }

  async validateTicket(ticketId: string, eventId: string): Promise<ValidateTicketResponseDto> {
    const ticket = await this.getTicket(ticketId);

    if (!ticket) {
      return {
        isValid: false,
        ticketId,
        eventId,
        message: 'Ticket not found',
      };
    }

    if (ticket.eventId !== eventId) {
      return {
        isValid: false,
        ticketId,
        eventId,
        message: 'Ticket does not belong to this event',
      };
    }

    if (ticket.isUsed) {
      return {
        isValid: false,
        ticketId,
        eventId,
        message: 'Ticket has already been used',
      };
    }

    return {
      isValid: true,
      ticketId,
      eventId,
      message: 'Ticket is valid',
    };
  }

  private mapTicketFields(id: string, fields: Record<string, unknown>): TicketResponseDto {
    return {
      id,
      eventId: fields.event_id as string,
      owner: fields.owner as string,
      originalOwner: fields.original_owner as string,
      ticketNumber: Number(fields.ticket_number),
      purchasePrice: fields.purchase_price as string,
      purchasedAt: fields.purchased_at as string,
      isUsed: fields.is_used as boolean,
      usedAt: fields.used_at as string | undefined,
      encryptedData: fields.encrypted_data as string | undefined,
    };
  }
}