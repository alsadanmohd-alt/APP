import test from 'node:test';
import assert from 'node:assert/strict';
import {daysBetween,distanceKm,approximate,normalizePhone} from '../lib/domain.mjs';
test('normalize Saudi local and international phone numbers',()=>{assert.equal(normalizePhone('٠٥٠١٢٣٤٥٦٧'),'+966501234567');assert.equal(normalizePhone('00966 50 123 4567'),'+966501234567');assert.equal(normalizePhone('+44 7700 900123'),'+447700900123');assert.throws(()=>normalizePhone('user@example.com'));assert.throws(()=>normalizePhone('123'))});
test('rental billing excludes return day across month and leap boundaries',()=>{assert.equal(daysBetween('2028-02-28','2028-03-01'),2);assert.equal(daysBetween('2026-12-31','2027-01-01'),1)});
test('reject reversed, equal and missing dates',()=>{assert.equal(daysBetween('2026-09-10','2026-09-09'),0);assert.equal(daysBetween('2026-09-10','2026-09-10'),0);assert.equal(daysBetween('',''),0)});
test('distance works at same point and across the international date line',()=>{assert.equal(distanceKm({lat:24,lng:46},{lat:24,lng:46}),0);const d=distanceKm({lat:0,lng:179.9},{lat:0,lng:-179.9});assert.ok(d>22&&d<23)});
test('public cell does not preserve precise coordinates',()=>{assert.equal(approximate(24.781234),24.78);assert.equal(approximate(46.634567),46.63)});
