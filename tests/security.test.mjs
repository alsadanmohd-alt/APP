// Run only against a disposable test Supabase project with schema.sql applied.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
const url=process.env.TEST_SUPABASE_URL,key=process.env.TEST_SUPABASE_ANON_KEY,service=process.env.TEST_SUPABASE_SERVICE_ROLE_KEY;
test('RLS, contact validation, private locations, chat, edit/delete',{skip:!(url&&key&&service)},async()=>{
 const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});const clients=[],users=[],itemIds=[];
 const ok=r=>{assert.equal(r.error,null,JSON.stringify(r.error));return r.data};
 try{
  for(let i=0;i<3;i++){const email=`qareeb-test-${crypto.randomUUID()}@example.com`,password=`T-${crypto.randomUUID()}!`;const u=ok(await admin.auth.admin.createUser({email,password,email_confirm:true})).user;users.push(u.id);const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});ok(await client.auth.signInWithPassword({email,password}));clients.push(client)}
  const [owner,renter,stranger]=clients;
  assert.ok((await owner.rpc('create_item',{p_title:'اختبار أمني',p_description:'غرض مؤقت للاختبارات الآلية',p_category:'تصوير',p_price:75,p_phone:'0555555555',p_area:'الرياض',p_lat:24.781234,p_lng:46.634567,p_images:[]})).error);
  const id=ok(await owner.rpc('create_item',{p_title:'اختبار أمني',p_description:'غرض مؤقت للاختبارات الآلية',p_category:'تصوير',p_price:75,p_phone:'+966555555555',p_area:'الرياض',p_lat:24.781234,p_lng:46.634567,p_images:[]}));itemIds.push(id);
  const publicItem=ok(await stranger.from('items').select('*').eq('id',id).single());assert.equal(publicItem.lat,24.78);assert.equal(publicItem.lng,46.63);assert.equal(publicItem.contact_phone,'+966555555555');
  assert.ok((await stranger.from('item_locations').select('*').eq('item_id',id)).error);
  assert.ok((await stranger.rpc('get_pickup_distance',{p_item:id,p_lat:24.78,p_lng:46.63})).error);

  // No approval step: starting a conversation works immediately and is idempotent per renter.
  const booking=ok(await renter.rpc('start_conversation',{p_item:id}));
  assert.equal(ok(await renter.rpc('start_conversation',{p_item:id})),booking);
  assert.equal(ok(await stranger.from('bookings').select('*').eq('id',booking)).length,0);
  assert.ok(ok(await renter.rpc('get_pickup_distance',{p_item:id,p_lat:24.78,p_lng:46.63}))>=0);
  assert.ok(ok(await owner.rpc('get_pickup_distance',{p_item:id,p_lat:24.78,p_lng:46.63}))>=0);
  assert.ok((await stranger.rpc('get_pickup_distance',{p_item:id,p_lat:24.78,p_lng:46.63})).error);

  // Chat is open from the start, no acceptance needed.
  ok(await renter.from('messages').insert({booking_id:booking,sender_id:users[1],body:'رسالة خاصة'}));
  assert.equal(ok(await stranger.from('messages').select('*').eq('booking_id',booking)).length,0);
  assert.ok((await stranger.from('messages').insert({booking_id:booking,sender_id:users[2],body:'غير مصرح'})).error);

  // Reviews only require an existing conversation and belong to the renter; no completion step exists.
  assert.ok((await stranger.from('reviews').insert({booking_id:booking,item_id:id,author_id:users[2],rating:5,body:'not mine'})).error);
  ok(await renter.from('reviews').insert({booking_id:booking,item_id:id,author_id:users[1],rating:5,body:'ممتاز'}));

  // Mirror: only the owner of the conversation can rate the renter, and only as themselves.
  assert.ok((await renter.from('renter_reviews').insert({booking_id:booking,renter_id:users[1],author_id:users[1],rating:5,body:'not mine'})).error);
  assert.ok((await stranger.from('renter_reviews').insert({booking_id:booking,renter_id:users[1],author_id:users[2],rating:5,body:'not mine'})).error);
  ok(await owner.from('renter_reviews').insert({booking_id:booking,renter_id:users[1],author_id:users[0],rating:4,body:'مستأجر ملتزم'}));
  assert.equal(ok(await stranger.from('renter_reviews').select('*').eq('booking_id',booking)).length,1);

  // Owner can edit; nobody else can. The exact pickup point is only readable by the owner.
  assert.ok((await renter.rpc('update_item',{p_id:id,p_title:'تعديل غير مصرح',p_description:'غرض مؤقت للاختبارات الآلية',p_category:'تصوير',p_price:80,p_phone:'+966555555555',p_area:'الرياض',p_lat:24.78,p_lng:46.63})).error);
  ok(await owner.rpc('update_item',{p_id:id,p_title:'اختبار أمني معدّل',p_description:'غرض مؤقت للاختبارات الآلية',p_category:'تصوير',p_price:90,p_phone:'+966555555555',p_area:'الرياض',p_lat:24.781234,p_lng:46.634567}));
  assert.equal(ok(await stranger.from('items').select('title,daily_price').eq('id',id).single()).daily_price,90);
  assert.ok((await renter.rpc('get_owner_item_location',{p_item:id})).error);
  const ownLoc=ok(await owner.rpc('get_owner_item_location',{p_item:id}));assert.equal(ownLoc[0].lat,24.781234);

  // Only the owner can delete, and it cascades to the conversation, its messages and both reviews.
  const deletedByOther=ok(await renter.from('items').delete().eq('id',id).select());assert.equal(deletedByOther.length,0);
  assert.ok(ok(await stranger.from('items').select('id').eq('id',id)).length===1);
  ok(await owner.from('items').delete().eq('id',id));
  assert.equal(ok(await admin.from('bookings').select('id').eq('id',booking)).length,0);
  assert.equal(ok(await admin.from('messages').select('id').eq('booking_id',booking)).length,0);
  assert.equal(ok(await admin.from('reviews').select('id').eq('booking_id',booking)).length,0);
  assert.equal(ok(await admin.from('renter_reviews').select('id').eq('booking_id',booking)).length,0);
  itemIds.length=0;
 }finally{
  if(itemIds.length){const bs=ok(await admin.from('bookings').select('id').in('item_id',itemIds)).map(b=>b.id);if(bs.length){ok(await admin.from('messages').delete().in('booking_id',bs));ok(await admin.from('reviews').delete().in('booking_id',bs));ok(await admin.from('renter_reviews').delete().in('booking_id',bs))}ok(await admin.from('bookings').delete().in('item_id',itemIds));ok(await admin.from('items').delete().in('id',itemIds))}
  for(const id of users)await admin.auth.admin.deleteUser(id);
 }
});
