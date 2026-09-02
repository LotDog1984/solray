import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  console.log('Seeding database...');

  // Hidden test admin account (platform testing only)
  const testEmail = 'abacus-21d1d168@example.com';
  const testPassword = '8fDg9U9*3b';
  const hashedTestPassword = await bcrypt.hash(testPassword, 12);

  await prisma.user.upsert({
    where: { email: testEmail },
    update: { password: hashedTestPassword, role: 'ADMIN', active: true },
    create: {
      name: 'Test Admin',
      email: testEmail,
      password: hashedTestPassword,
      role: 'ADMIN',
      active: true,
    },
  });

  console.log('Database seeded successfully!');
}

main()
  .catch((e) => {
    console.error('Seed error:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
