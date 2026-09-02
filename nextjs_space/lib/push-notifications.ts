import { prisma } from '@/lib/prisma';

interface ExpoPushMessage {
  to: string;
  title: string;
  body: string;
  data?: Record<string, any>;
  sound?: string;
}

export async function sendPushNotifications(
  userIds: string[],
  title: string,
  body: string,
  data?: Record<string, any>
) {
  try {
    const tokens = await prisma.pushToken.findMany({
      where: { userId: { in: userIds } },
      select: { token: true },
    });

    if (tokens?.length === 0) return;

    const messages: ExpoPushMessage[] = (tokens ?? []).map((t: any) => ({
      to: t?.token ?? '',
      title,
      body,
      data: data ?? {},
      sound: 'default',
    }));

    const validMessages = messages.filter((m: ExpoPushMessage) => m?.to?.length > 0);
    if (validMessages?.length === 0) return;

    const response = await fetch('https://exp.host/--/api/v2/push/send', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(validMessages),
    });

    if (!response?.ok) {
      console.error('Expo Push API error:', await response?.text?.());
    }
  } catch (error) {
    console.error('Failed to send push notifications:', error);
  }
}

export async function createInAppNotification(
  userId: string,
  type: 'TASK_ASSIGNED' | 'COMMENT_ADDED' | 'PROJECT_MEMBER_ADDED' | 'PROJECT_MEMBER_REMOVED',
  title: string,
  message: string,
  data?: Record<string, any>
) {
  try {
    await prisma.notification.create({
      data: {
        userId,
        type,
        title,
        message,
        data: data ?? {},
      },
    });
  } catch (error) {
    console.error('Failed to create notification:', error);
  }
}
