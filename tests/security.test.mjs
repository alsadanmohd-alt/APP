// Run only against a disposable test Supabase project with schema.sql applied.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
const url=process.env.TEST_SUPABASE_URL,key=process.env.TEST_SUPABASE_ANON_KEY,service=process.env.TEST_SUPABASE_SERVICE_ROLE_KEY;
test('RLS, contact validation, private locations and chat',{skip:!(url&&key&&service)},async()=>{
 const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});const clients=[],users=[],itemIds=[];
 const ok=r=>{assert.equal(r.error,null,JSON.stringify(r.error));return r.data};
 try{
  for(let i=0;i<3;i++){const email=`qareeb-test-${crypto.randomUUID()}@example.com`,password=`T-${crypto.randomUUID()}!`;const u=ok(await admin.auth.admin.createUser({email,password,email_confirm:true})).user;users.push(u.id);const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});ok(await client.auth.signInWithPassword({email,password}));clients.push(client)}
  const [owner,renter,stranger]=clients;
  assert.ok((await owner.rpc('create_item',{p_title:'اختبار أمني',p_description:'غرض مؤقت للاختبارات الآلية',p_category:'تصوير',p_price:75,p_phone:'0555555555',p_area:'الرياض',p_lat:24.781234,p_lng:46.634567,p_images:[]})).error);
  const id=ok(await owner.rpc('create_item',{p_title:'اختبار أمني',p_description:'غرض مؤقت للاختبارات الآلية',p_category:'تصوير',p_price:75,p_phone:'+966555555555',p_area:'الرياض',p_lat:24.781234,p_lng:46.634567,p_images:[]}));itemIds.push(id);
  const publicItem=ok(await stranger.from('items').select('*').eq('id',id).single());assert.equal(publicItem.lat,24.78);assert.equal(publicItem.lng,46.63);assert.equal(publicItem.contact_phone,'+966555555555');
  assert.equal(ok(await stranger.from('item_locations').select('*').eq('item_id',id)).length,0);
  const booking=ok(await renter.rpc('request_contact',{p_item:id}));
  assert.ok((await renter.rpc('request_contact',{p_item:id})).error);
  assert.equal(ok(await stranger.from('bookings').select('*').eq('id',booking)).length,0);
  assert.equal(ok(await renter.from('item_locations').select('*').eq('item_id',id)).length,0);
  assert.ok((await renter.rpc('change_booking',{p_booking:booking,p_status:'accepted'})).error);
  assert.ok((await renter.from('bookings').update({status:'accepted'}).eq('id',booking)).error);
  assert.ok((await renter.from('reviews').insert({booking_id:booking,item_id:id,author_id:users[1],rating:5,body:'premature'})).error);
  ok(await renter.from('messages').insert({booking_id:booking,sender_id:users[1],body:'رسالة خاصة'}));
  assert.equal(ok(await stranger.from('messages').select('*').eq('booking_id',booking)).length,0);
  assert.ok((await stranger.from('messages').insert({booking_id:booking,sender_id:users[2],body:'غير مصرح'})).error);
  const otherRequest=ok(await stranger.rpc('request_contact',{p_item:id}));
  ok(await owner.rpc('change_booking',{p_booking:booking,p_status:'accepted'}));
  assert.equal(ok(await renter.from('item_locations').select('*').eq('item_id',id).single()).lat,24.781234);
  assert.equal(ok(await stranger.from('item_locations').select('*').eq('item_id',id)).length,0);
  ok(await owner.rpc('change_booking',{p_booking:otherRequest,p_status:'rejected'}));
 }finally{
  if(itemIds.length){const bs=ok(await admin.from('bookings').select('id').in('item_id',itemIds)).map(b=>b.id);if(bs.length){ok(await admin.from('messages').delete().in('booking_id',bs));ok(await admin.from('reviews').delete().in('booking_id',bs))}ok(await admin.from('bookings').delete().in('item_id',itemIds));ok(await admin.from('items').delete().in('id',itemIds))}
  for(const id of users)await admin.auth.admin.deleteUser(id);
 }
});
