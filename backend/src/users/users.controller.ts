import { Controller, Get, Param } from '@nestjs/common';
import { ApiOperation, ApiParam, ApiResponse, ApiTags } from '@nestjs/swagger';
import { UsersService } from './users.service';
import { UserProfileResponseDto } from './dto/user.dto';

@ApiTags('users')
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get('profile/:id')
  @ApiOperation({ summary: 'Get user profile by profile ID' })
  @ApiParam({ name: 'id', description: 'User profile object ID' })
  @ApiResponse({ status: 200, type: UserProfileResponseDto })
  async getUserProfile(@Param('id') id: string): Promise<UserProfileResponseDto | null> {
    return this.usersService.getUserProfile(id);
  }

  @Get('address/:address')
  @ApiOperation({ summary: 'Get user profile by wallet address' })
  @ApiParam({ name: 'address', description: 'User wallet address' })
  @ApiResponse({ status: 200, type: UserProfileResponseDto })
  async getUserProfileByAddress(
    @Param('address') address: string,
  ): Promise<UserProfileResponseDto | null> {
    return this.usersService.getUserProfileByAddress(address);
  }

  @Get('username/:username/exists')
  @ApiOperation({ summary: 'Check if username exists' })
  @ApiParam({ name: 'username', description: 'Username to check' })
  @ApiResponse({ status: 200, type: Boolean })
  async checkUsernameExists(@Param('username') username: string): Promise<boolean> {
    return this.usersService.checkUsernameExists(username);
  }
}