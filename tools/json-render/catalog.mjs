import { z } from 'zod';
import { defineCatalog } from '@json-render/core';
import { schema } from '@json-render/react/schema';
import { shadcnComponentDefinitions } from '@json-render/shadcn/catalog';
import { standardDirectives, createI18nDirective } from '@json-render/directives';

export const directives = [...standardDirectives, createI18nDirective({locale:'ja', messages:{ja:{yes:'はい', no:'いいえ', total:'合計'}}})];
export const definitions = {
  ...shadcnComponentDefinitions,
  Metric: {props:z.object({label:z.string(),value:z.union([z.string(),z.number()]),detail:z.string().nullable()}),description:'A source-backed metric with label, value and optional detail.'},
  BarChart: {props:z.object({title:z.string(),unit:z.string().nullable(),items:z.array(z.object({label:z.string(),value:z.number()})).max(100)}),description:'Accessible bar chart. Only use actual source values; include their unit.'},
  Panel: {props:z.object({label:z.string().nullable()}),slots:['default','header','footer'],description:'A section with named header/footer slots and default children.'},
};
export const actionDefinitions = {
  copyText:{params:z.object({text:z.string().max(16000)}),description:'Copy text after the person activates a control.'},
  openURL:{params:z.object({url:z.string().url().max(2048)}),description:'Ask the person to open an HTTPS link. Never opens automatically.'},
  askAI:{params:z.object({prompt:z.string().max(8000)}),description:'Stage an editable question in the Ask AI composer, without sending it or replacing a draft.'},
  completeTask:{params:z.object({id:z.string().uuid()}),description:'Request task completion using a UUID returned by list_tasks in this answer. The native approval card is always required.'},
};
export const catalog = defineCatalog(schema,{components:definitions,actions:actionDefinitions});
export const builtInActions = new Set(['setState','pushState','removeState','validateForm','push','pop']);
export const functions = {
  sum:({values=[]})=>values.reduce((sum,value)=>sum+(Number(value)||0),0),
  average:({values=[]})=>values.length ? values.reduce((sum,value)=>sum+(Number(value)||0),0)/values.length : 0,
  count:({values=[]})=>values.length,
  min:({values=[]})=>values.length ? Math.min(...values.map(Number)) : 0,
  max:({values=[]})=>values.length ? Math.max(...values.map(Number)) : 0,
};
