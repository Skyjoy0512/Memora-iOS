import React from 'react';
import {defineRegistry} from '@json-render/react';
import {shadcnComponents} from '@json-render/shadcn';
import {catalog} from './catalog.mjs';
const Metric=({props})=><section className="metric"><p>{props.label}</p><strong>{props.value}</strong>{props.detail&&<p>{props.detail}</p>}</section>;
const BarChart=({props})=>{
  const maximum=Math.max(1,...props.items.map(item=>Math.abs(item.value)));
  return <section aria-label={props.title}><h3>{props.title}</h3><dl>{props.items.map((item,index)=><div key={index} className="chart-row"><dt>{item.label}</dt><dd><div role="img" aria-label={`${item.label}: ${item.value} ${props.unit??''}`} className="chart-bar" style={{width:`${Math.max(1,Math.abs(item.value)/maximum*100)}%`}}/><span>{item.value.toLocaleString('ja-JP')} {props.unit}</span></dd></div>)}</dl></section>;
};
const Panel=({props,children,slots})=><section aria-label={props.label??undefined} className="panel">{slots?.header&&<header>{slots.header}</header>}{children}{slots?.footer&&<footer>{slots.footer}</footer>}</section>;
export const {registry}=defineRegistry(catalog,{components:{...shadcnComponents,Metric,BarChart,Panel}});

