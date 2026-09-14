import { Router, Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../config/database';
import { authenticate, requireRole } from '../middleware/auth';

const router = Router();

router.post('/create', authenticate, async (req: Request, res: Response) => {
  try {
    const { name } = req.body;
    const ownerUid = req.user!.uid;

    if (!name) {
      res.status(400).json({ error: 'Agency name is required' });
      return;
    }

    const code = 'AG' + String(1000 + Math.floor(Math.random() * 9000));

    const agencyId = uuidv4();
    const agency = {
      id: agencyId,
      name,
      code,
      owner_uid: ownerUid,
      commission_rate: 10,
      total_earnings: 0,
      member_count: 1,
      status: 'active',
      created_at: new Date().toISOString(),
    };

    await db.collection('agencies').doc(agencyId).set(agency);

    await db.collection('users').doc(ownerUid).set({ role: 'agent', agency_id: agencyId }, { merge: true });

    res.status(201).json({ agency });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/my', authenticate, async (req: Request, res: Response) => {
  try {
    const uid = req.user!.uid;

    const membershipSnap = await db
      .collection('agency_members')
      .where('user_uid', '==', uid)
      .limit(1)
      .get();

    const agencyId = membershipSnap.empty ? undefined : membershipSnap.docs[0].data().agency_id;

    let agencyDoc = null;
    if (agencyId) {
      agencyDoc = await db.collection('agencies').doc(agencyId).get();
    }

    if (!agencyId || !agencyDoc!.exists) {
      const ownedSnap = await db
        .collection('agencies')
        .where('owner_uid', '==', uid)
        .limit(1)
        .get();

      if (!ownedSnap.empty) {
        const ownedAgency = ownedSnap.docs[0].data();
        const membersSnap = await db
          .collection('agency_members')
          .where('agency_id', '==', ownedAgency.id)
          .get();

        res.json({
          agency: ownedAgency,
          members: membersSnap.docs.map(d => d.data()),
        });
        return;
      }

      res.json({ agency: null, members: [] });
      return;
    }

    const membersSnap = await db
      .collection('agency_members')
      .where('agency_id', '==', agencyId)
      .get();

    res.json({
      agency: agencyDoc!.data(),
      members: membersSnap.docs.map(d => d.data()),
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/join', authenticate, async (req: Request, res: Response) => {
  try {
    const { code } = req.body;
    const userUid = req.user!.uid;

    if (!code) {
      res.status(400).json({ error: 'Agency code is required' });
      return;
    }

    const agencySnap = await db.collection('agencies').where('code', '==', code).limit(1).get();
    if (agencySnap.empty) {
      res.status(404).json({ error: 'Agency not found' });
      return;
    }

    const agencyDoc = agencySnap.docs[0];
    const agency = agencyDoc.data() as any;

    if (agency.status !== 'active') {
      res.status(400).json({ error: 'Agency is suspended' });
      return;
    }

    const existingSnap = await db
      .collection('agency_members')
      .where('agency_id', '==', agency.id)
      .where('user_uid', '==', userUid)
      .limit(1)
      .get();

    if (!existingSnap.empty) {
      res.status(400).json({ error: 'Already a member of this agency' });
      return;
    }

    const memberId = uuidv4();
    const member = {
      id: memberId,
      agency_id: agency.id,
      user_uid: userUid,
      role: 'sub_agent',
      commission_rate: agency.commission_rate - 2,
      joined_at: new Date().toISOString(),
    };

    await db.runTransaction(async tx => {
      tx.set(db.collection('agency_members').doc(memberId), member);
      tx.update(db.collection('agencies').doc(agencyDoc.id), {
        member_count: FieldValue.increment(1),
      });
    });

    await db.collection('users').doc(userUid).set({ role: 'agent', agency_id: agency.id }, { merge: true });

    res.status(201).json({ agency, member });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/add-agent', authenticate, requireRole('admin'), async (req: Request, res: Response) => {
  try {
    const { agencyId, userUid, commissionRate } = req.body;

    const memberId = uuidv4();
    const member = {
      id: memberId,
      agency_id: agencyId,
      user_uid: userUid,
      role: 'agent',
      commission_rate: commissionRate || 10,
      joined_at: new Date().toISOString(),
    };

    await db.collection('agency_members').doc(memberId).set(member);

    await db.collection('users').doc(userUid).set({ role: 'agent', agency_id: agencyId }, { merge: true });

    res.status(201).json({ member });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/all', authenticate, requireRole('admin'), async (_req: Request, res: Response) => {
  try {
    const snap = await db.collection('agencies').orderBy('created_at', 'desc').get();

    res.json({ agencies: snap.docs.map(d => d.data()) });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/v1/agencies/withdraw
 * Allows agency owner to request diamond withdrawal (USDT TRC20 / Bank).
 */
router.post('/withdraw', authenticate, async (req: Request, res: Response) => {
  const uid = req.user?.uid;
  if (!uid) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  const { agencyId, diamonds: rawDiamonds, payoutMethod, payoutAddress, accountDetails } = req.body ?? {};
  const diamonds = Math.trunc(Number(rawDiamonds) || 0);

  if (!agencyId || diamonds < 5000) {
    res.status(400).json({ error: 'Invalid parameters: minimum withdrawal is 5,000 diamonds ($5.00)' });
    return;
  }

  const method = String(payoutMethod ?? 'usdt_trc20');
  const address = String(payoutAddress ?? accountDetails ?? '').trim();
  if (!address) {
    res.status(400).json({ error: 'Payout address or account details required' });
    return;
  }

  try {
    const agencyRef = db.collection('host_agencies').doc(agencyId);
    const agencyWalletRef = db.collection('agency_wallets').doc(agencyId);
    const withdrawalId = uuidv4();
    const now = new Date().toISOString();
    const usdEquivalent = Math.round((diamonds / 1000) * 100) / 100;

    await db.runTransaction(async (txn) => {
      const [aSnap, wSnap] = await Promise.all([
        txn.get(agencyRef),
        txn.get(agencyWalletRef),
      ]);

      if (!aSnap.exists) {
        throw new Error('agency_not_found');
      }
      const aData = aSnap.data() ?? {};
      if (String(aData.owner_id ?? aData.owner_uid ?? '') !== uid) {
        throw new Error('forbidden_not_agency_owner');
      }

      const wData = wSnap.exists ? (wSnap.data() ?? {}) : {};
      const currentBalance = Math.trunc(Number(wData.diamond_balance ?? 0));
      if (currentBalance < diamonds) {
        throw new Error('insufficient_diamond_balance');
      }

      txn.set(
        agencyWalletRef,
        {
          diamond_balance: FieldValue.increment(-diamonds),
          total_withdrawn_diamonds: FieldValue.increment(diamonds),
          updated_at: now,
        },
        { merge: true },
      );

      txn.set(db.collection('agency_withdrawals').doc(withdrawalId), {
        id: withdrawalId,
        agency_id: agencyId,
        owner_id: uid,
        amount_diamonds: diamonds,
        usd_amount: usdEquivalent,
        payout_method: method,
        payout_address: address,
        status: 'pending',
        created_at: now,
      });
    });

    res.json({
      success: true,
      withdrawal_id: withdrawalId,
      diamonds_withdrawn: diamonds,
      usd_amount: usdEquivalent,
      status: 'pending',
    });
  } catch (err: any) {
    res.status(400).json({ error: err.message || 'withdrawal_failed' });
  }
});

/**
 * GET /api/v1/agencies/:id/withdrawals
 * Retrieves withdrawal history for an agency.
 */
router.get('/:id/withdrawals', authenticate, async (req: Request, res: Response) => {
  const agencyId = req.params.id;
  try {
    const snap = await db
      .collection('agency_withdrawals')
      .where('agency_id', '==', agencyId)
      .orderBy('created_at', 'desc')
      .limit(50)
      .get();

    res.json({ withdrawals: snap.docs.map((d) => d.data()) });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

export default router;

